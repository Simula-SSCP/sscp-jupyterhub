GKE_PROJECT=sscp-2026
IMAGE_TAG=2026
GKE_REGION=europe-west1
GKE_ZONE=$(GKE_REGION)-b
IMAGE=$(GKE_REGION)-docker.pkg.dev/$(GKE_PROJECT)/sss/simula-summer-school:$(IMAGE_TAG)
KUBE_CTX=sss
NS=jupyterhub
BUILDER_NAME=sss-builder

ifeq ($(PUSH), 1)
  IMAGE_PUSH=--push
endif

.PHONY: image image-test push conda-rsync conda-fetch tofu kube-creds builder-new

image-push:
	make image PUSH=1

image: $(wildcard image/*)
	docker buildx build --platform linux/amd64 $(IMAGE_PUSH) --load -t $(IMAGE) image

image/pixi.lock: image/pixi.toml
	cd image; pixi update --no-install

image-test:
	docker buildx build --load -t image-test --build-arg IMAGE=$(IMAGE) image-test
	docker run --rm -it image-test pytest -vs $(ARG)

dive:
	dive $(IMAGE)

push-creds:
	gcloud auth configure-docker $(GKE_REGION)-docker.pkg.dev

push:
	docker push $(IMAGE)

# list images
# gcloud compute images list --filter=name=ubuntu

# https://gitlab.com/gitlab-org/ci-cd/docker-machine/-/issues/47
# Error 404: The resource 'projects/simula-summer-school-2023/global/firewalls/docker-machines' was not found, notFound

# builder-firewall-rule before builder-new
builder-firewall-rule:
	gcloud --project=$(GKE_PROJECT) compute firewall-rules create docker-machines --allow=tcp:22

builder-new:
	gcloud compute instances create $(BUILDER_NAME) \
		--project=$(GKE_PROJECT) \
		--zone=$(GKE_ZONE) \
		--preemptible \
		--machine-type=e2-standard-4 \
		--boot-disk-size=100 \
		--boot-disk-type=pd-balanced \
		--image-project=ubuntu-os-cloud \
		--image-family=ubuntu-minimal-2404-lts-amd64
	gcloud compute config-ssh --project=$(GKE_PROJECT)
	# seems to need to wait to boot
	sleep 20
	$(MAKE) builder-setup-docker

builder-setup-docker:
	# setup docker
	gcloud compute ssh --project=$(GKE_PROJECT) --zone=$(GKE_ZONE) $(BUILDER_NAME) -- "curl https://get.docker.com | bash; sudo usermod -aG docker $$(whoami)"
	# setup rsync
	gcloud compute ssh --project=$(GKE_PROJECT) --zone=$(GKE_ZONE) $(BUILDER_NAME) -- 'sudo apt-get -y install rsync'
	gcloud compute ssh --project=$(GKE_PROJECT) --zone=$(GKE_ZONE) $(BUILDER_NAME) -- 'sudo mkdir -p $(PWD) && sudo chown $$(whoami) $(PWD)'

builder-start:
	gcloud compute instances start --project=$(GKE_PROJECT) --zone=$(GKE_ZONE) $(BUILDER_NAME)
	# reload
	gcloud compute config-ssh --project=$(GKE_PROJECT)

builder-env:
	@echo "export DOCKER_HOST=ssh://$(BUILDER_NAME).$(GKE_ZONE).$(GKE_PROJECT)"

builder-rm:
	gcloud compute instances delete --project=$(GKE_PROJECT) --zone=$(GKE_ZONE) $(BUILDER_NAME)

tofu:
	cd tofu; tofu init -upgrade; tofu apply

kube-creds:
	gcloud --project=$(GKE_PROJECT) container clusters get-credentials --region $(GKE_REGION) $(KUBE_CTX)
	kubectx $(KUBE_CTX)=.
	kubens jupyterhub

HELM_ARGS := hub --namespace=$(NS) --kube-context=$(KUBE_CTX) ./jupyterhub -f config.yaml -f secrets.yaml

helm-diff:
	helm diff upgrade $(HELM_ARGS)

helm-upgrade:
	helm dep up ./jupyterhub
	helm upgrade --install --cleanup-on-fail $(HELM_ARGS)

conda:
	docker build -t conda-pkgs conda-recipes

conda-rsync:
	rsync -av --delete -e 'gcloud compute ssh --project $(GKE_PROJECT) --zone $(GKE_ZONE) $(BUILDER_NAME) --' conda-recipes/ env:$(PWD)/conda-recipes/

conda-fetch:
	rsync -av --delete -e 'gcloud compute ssh --project $(GKE_PROJECT) --zone $(GKE_ZONE) $(BUILDER_NAME) --' env:$(PWD)/conda-bld/linux-64/ $(PWD)/conda-bld/linux-64/
	
conda/%: conda conda-rsync
	docker run --rm -it -e CPU_COUNT=4 -u 1001 -v $(PWD)/conda-bld:/io/conda-bld -v $(PWD)/conda-recipes:/conda-recipes -v /tmp/conda-pkgs:/opt/conda/pkgs conda-pkgs build-conda /conda-recipes/$*

conda-upload/%:
	docker run --rm -it -v $(PWD)/conda-bld:/io/conda-bld conda-pkgs sh -c 'anaconda upload /io/conda-bld/linux-64/$*-*.conda'

run:
	docker run -it --rm -p9999:8888 $(IMAGE) $(ARG)

pull:
	- $(foreach instance, \
		$(shell gcloud compute instances list --format json --project=$(GKE_PROJECT) | jq -r ".[].name"), \
  		gcloud --project=$(GKE_PROJECT) compute ssh --zone=$(GKE_ZONE) $(instance) -- docker pull $(IMAGE);)

clean-jobs:
	kubectl --context=$(KUBE_CTX) delete jobs $(shell kubectl get jobs -a | sed '1d' | awk '{print $$1}')
