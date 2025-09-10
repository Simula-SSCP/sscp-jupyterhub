# simula summer school deployment

deployment config for simula SUURPh summer school at simula

## Requirements

You need to setup and enable the [gcloud cli].
You need these tools set up:

- make
- [gcloud cli]
- [OpenTofu]
- [pixi]
- [docker] client (engine not required, but can be used)
- [helm] to deploy and update jupyterhub
- [git-crypt] for encrypting credentials in config

[gcloud cli]: https://cloud.google.com/cli
[OpenTofu]: https://opentofu.org
[pixi]: https://pixi.sh
[docker]: https://www.docker.com
[helm]: https://helm.sh
[git-crypt]: https://github.com/AGWA/git-crypt

## Structure

Automation is important in this repo because mosts tasks are only run a few times a year. They will be forgotten!

Most operations in this repo are represented as `make` targets.
If you add a task, add a `make` target for easier remembering/re-use
(or migrate to snakemake/nox/invoke/whatever task tool you like).

These tools are used:

- google cloud hosts the deployment, using GKE (switched to Autopilot in 2025 to try to reduce costs, it didn't seem to improve things, so going back to 2024 should give more portability)
- OpenTofu deploys the cloud resources (the kubernetes cluster itself, node pools)
- rattler-build is used to build packages not yet on conda-forge (currently only OpenCARP)
- helm deploys and updates JupyterHub itself

### Repo content

The repo contains:

- conda-recipes: recipes for building custom packages, not already packaged on conda-forge.
- image: defining the user environment
- image-test: test files for validating the user image
- tofu: OpenTofu configuration for deploying the cluster
- jupyterhub: the helm chart
- config.yaml: helm chart configuration
- secrets.yaml: additional helm chart configuration, encrypted with [git-crypt]
- repos.txt: repo URLs pulled at launch time with a light version of nbgitpuller (usually just the lectures repo)

## Initial setup

### Create gcloud project

When setting up the JupyterHub deployment for the new year (typically in April),
the first step is to create a "Google Cloud Project" at https://console.cloud.google.com/projectcreate .

- Make sure to create it with your Simula account and in the Simula organization.
- Hook it up to the billing account "SSCP" id: 01868E-716AD7-9AEC96.
  You may not have a choice at project creation time.
  You can change project billing at https://console.cloud.google.com/billing/projects

I usually call this project `sscp-YYYY` e.g. `sscp-2025` for the 2025 deployment.
The project will be deleted at the end of the summer to ensure there are no ongoing costs.

- Update the variable `GKE_PROJECT` in `Makefile` with the new project id.

We need to enable these APIs:

- artifact registry (storing container images)
- kubernetes engine (the deployment itself)

### Updating the image and packages to get started

- update GKE_PROJECT in Makefile
- update IMAGE_TAG in Makefile
- update versions in `tofu/main.tf`
- deploy cloud resources with tofu (more below)
- update opencarp packages in `conda-recipes`, if necessary (usually needed, because of petsc version pinning)
- update helm chart dependency versions in `jupyterhub/Chart.yaml`
- update packages in `image/pixi.toml` and update the image (see below)
- update `jupyterhub.singleuser.image` to match GKE_PROJECT and IMAGE_TAG

## Actions

### Unlocking the repo with git-crypt

The `secrets.yaml` file is encrypted with git-crypt.

See the [mybinder-sre guide](https://mybinder-sre.readthedocs.io/en/latest/getting_started/production_environment.html#sharing-secrets) on sharing a git-crypt secret and unlocking an encrypted repo.
This is only needed for contributors who want to modify the secrets or deploy a helm update,
otherwise the secrets can stay encrypted.

### Deploying cloud resources with Tofu

To deploy the cluster and cloud resources, first create a bucket at https://console.cloud.google.com/storage/create-bucket
that matches the `backend "gcs"` bucket name.
This name needs to change each year.

Then you can deploy any resources defined in `tofu/main.tf` with:

```
make tofu
```

This will create:

- artifact registry (for the image)
- GKE cluster (the actual deployment)

`make tofu` needs to be run quite rarely, maybe only once per year.
It only needs to run to change what's in `tofu/main.tf`.
If using autopilot,

Once the cluster is created, you can run

```
make kube-creds
```

to load the credentials into your `kubectl` config for accessing the cluster directly with `kubectl`.
This will have the name matching `KUBE_CTX` in the makefile (currently: `sss` for "Simula Summer School").

### Building the image

> **note:** I have historically built the image _on_ google cloud,
> because it's big and pushing a large image from google to google is fast.
> Firewall rules and things have made this a pain and error-prone,
> so switching to pushing from GitHub Actions probably makes sense as a trade-off.

The user image is defined in the [image/](./image/) folder.

The environment is locked, and defined in `pixi.toml`.
To add/remove/update packages, edit `pixi.toml`
and run

```
make image/pixi.lock
```

which will re-lock the environment

Then you can build the image.

To build the image on an google cloud spot instance:

```bash
make builder-firewall-rule
make builder-new
eval $(make builder-env)
make image
make push
```

Or you can build and push from anywhere with

```
make image
make push
```

which will likely be slower than pushing from within GCP.

You may need to:

```
make push-creds
```

to set up credentials for pushing to the registry.

### Testing the image

You can test the image with

```
make image-test
```

This loads the image built with `make image`, and runs `pytest` in the `image-test` directory.
Write any tests here that would be useful (e.g. running through a few sample lessons).
This should be part of building the image when adding image-building to CI.

### Scaling

To reduce costs, the initial scale when testing is small.
The main knobs for scaling are:

- node selectors (not used with autopilot)
- singleuser resource guarantees
- placeholder pods

During the initial setup, I usually set:

```yaml
userPlaceholder:
  replicas: 0
userScheduler:
  userPods:
    nodeAffinity:
      matchNodePurpose: prefer
```

And then when students are going to arrive, switch to:

```yaml
userPlaceholder:
  replicas: 10
userScheduler:
  userPods:
    nodeAffinity:
      matchNodePurpose: require
```

I then revert back to 0 replicas after the June session is over, and back again when August starts.

### Shutting down

By using a single project for each deployment,
shutting things down is just deleting the project from the cloud console.
That way you can be sure there aren't any lingering costs.

## Notes

### autopilot

The GKE cluster was switched to autopilot in 2025 to make some things easier and hopefully reduce costs.
This didn't really reduce costs, but it _also_ required removing a bunch of configuration that autopilot doesn't support:

- removed cert-manager from tofu deployment (see various tls, ingress changes)
- removed ingress-nginx (have to use gce)
- can't use node selectors

So a lot of that can probably be reverted and go back to a regular GKE cluster.
Check the helm chart-related changes in https://github.com/Simula-SSCP/sscp-jupyterhub/compare/2024...2025 for what to revert.
_most_ of it is still there, but commented out.

### OpenCARP

opencarp used to be a bit of a mess,
but with version 18, I think it might be in good enough shape to submit to conda-forge.
I'll try to find time to do this before the spring,
or someone can help.
It should mostly be moving the recipes here to conda-forge/staged-recipes.
Then we can lose the custom conda-building part, which would be excellent.
