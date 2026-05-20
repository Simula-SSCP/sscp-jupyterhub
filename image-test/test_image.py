import os
import sys
from pathlib import Path
from subprocess import run

import pytest

lectures_dir = "SSCP_lectures"


@pytest.fixture(scope="session")
def needs_puller():
    """Some tests need the puller to have run"""
    if not os.path.exists(lectures_dir):
        test_puller()


def test_puller_ext():
    from jupyter_core.paths import jupyter_config_path
    from jupyter_server.extension.config import ExtensionConfigManager
    from jupyter_server.extension.manager import ExtensionManager

    m = ExtensionManager(
        config_manager=ExtensionConfigManager(read_config_path=jupyter_config_path())
    )
    for name, ext in m.extensions.items():
        print(f"Validating extension {name}")
        # workaround
        for ep_name, extension_point in ext.extension_points.items():
            print(f"Validating extension {name}.{ep_name}")
            assert extension_point.validate() in {None, True}
        ext.validate()
    assert "pull_server_ext" in m.extensions


def test_puller():
    import pull_server_ext

    pull_server_ext.pull_everything()
    assert os.path.exists(lectures_dir)


def test_torch():
    import torch  # noqa


def test_dolfin():
    from dolfin import FiniteElement, FunctionSpace, UnitIntervalMesh, interval

    mesh = UnitIntervalMesh(20)
    elem = FiniteElement("CG", interval, 1)
    W = FunctionSpace(mesh, elem)


def test_dolfinx():
    # poisson tutorial
    # https://jsdokken.com/dolfinx-tutorial/chapter1/fundamentals_code.html
    from dolfinx import mesh
    from mpi4py import MPI

    domain = mesh.create_unit_square(MPI.COMM_WORLD, 8, 8, mesh.CellType.quadrilateral)

    from dolfinx.fem import functionspace

    V = functionspace(domain, ("Lagrange", 1))

    from dolfinx import fem

    uD = fem.Function(V)
    uD.interpolate(lambda x: 1 + x[0] ** 2 + 2 * x[1] ** 2)

    import numpy

    # Create facet to cell connectivity required to determine boundary facets
    tdim = domain.topology.dim
    fdim = tdim - 1
    domain.topology.create_connectivity(fdim, tdim)
    boundary_facets = mesh.exterior_facet_indices(domain.topology)

    boundary_dofs = fem.locate_dofs_topological(V, fdim, boundary_facets)
    bc = fem.dirichletbc(uD, boundary_dofs)

    import ufl

    u = ufl.TrialFunction(V)
    v = ufl.TestFunction(V)

    from dolfinx import default_scalar_type

    f = fem.Constant(domain, default_scalar_type(-6))

    a = ufl.dot(ufl.grad(u), ufl.grad(v)) * ufl.dx
    L = f * v * ufl.dx

    from dolfinx.fem.petsc import LinearProblem

    problem = LinearProblem(
        a, L, bcs=[bc], petsc_options={"ksp_type": "preonly", "pc_type": "lu"}
    )
    uh = problem.solve()


@pytest.mark.skip(reason="mshr not available")
def test_mshr():
    import mshr  # noqa


def test_neuron():
    from neuron import h, rxd  # noqa


@pytest.mark.parametrize(
    "notebook",
    [
        f"{lectures_dir}/L14 (FEniCS Mechanics)/L14_active_cube.ipynb",
        f"{lectures_dir}/L15 (EMI)/EMI.ipynb",
        # AI-LIF notebook is no longer complete (has fill-in exercises)
        # FIXME: there are no runnable pytorch notebooks
        # f"{lectures_dir}/L16 (Machine Learning)/AI-LIF.ipynb",
    ],
)
def test_notebook(notebook, needs_puller):
    import nbformat
    from nbconvert.preprocessors import ExecutePreprocessor

    with open(notebook) as f:
        nb = nbformat.read(f, as_version=4)
    p = ExecutePreprocessor()
    p.preprocess(nb)


@pytest.mark.parametrize(
    "run_dir",
    [
        f"{lectures_dir}/Stream 1 (Cardiac Simulations)/01_EP_single_cell/01_basic_bench",
    ],
)
def test_run(run_dir):
    run([sys.executable, Path(run_dir) / "run.py"], check=True)
