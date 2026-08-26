"""Windows build for the mesh_inpaint_processor extension.

Upstream ships compile_mesh_painter.sh, which calls `c++` and `python3-config`
-- neither exists on Windows. This builds the same pybind11 extension with MSVC.

Run from this directory, inside the activated conda env, after loading MSVC
(vcvars64.bat):

    python setup.py build_ext --inplace

The resulting .pyd must sit next to MeshRender.py, which imports it as
`from .mesh_inpaint_processor import meshVerticeInpaint`.
"""

from setuptools import setup
from pybind11.setup_helpers import Pybind11Extension, build_ext

ext_modules = [
    Pybind11Extension(
        "mesh_inpaint_processor",
        ["mesh_inpaint_processor.cpp"],
        cxx_std=11,
    ),
]

setup(
    name="mesh_inpaint_processor",
    version="0.1",
    ext_modules=ext_modules,
    cmdclass={"build_ext": build_ext},
)
