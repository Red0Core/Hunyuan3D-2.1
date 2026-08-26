# Modified by official-imvoiid (Hunyuan3D-2.1 Windows / 16GB VRAM fork).
# Changes: Windows kernel source directory and MSVC compile flags.

# Hunyuan 3D is licensed under the TENCENT HUNYUAN NON-COMMERCIAL LICENSE AGREEMENT
# except for the third-party components listed below.
# Hunyuan 3D does not impose any additional limitations beyond what is outlined
# in the repsective licenses of these third-party components.
# Users must comply with all terms and conditions of original licenses of these third-party
# components and must ensure that the usage of the third party components adheres to
# all relevant laws and regulations.

# For avoidance of doubts, Hunyuan 3D means the large language models and
# their software and algorithms, including trained model weights, parameters (including
# optimizer states), machine-learning model code, inference-enabling code, training-enabling code,
# fine-tuning enabling code and other elements of the foregoing made publicly available
# by Tencent in accordance with TENCENT HUNYUAN COMMUNITY LICENSE AGREEMENT.

import sys

from setuptools import setup, find_packages
import torch
from torch.utils.cpp_extension import BuildExtension, CUDAExtension, CppExtension

# build custom rasterizer

# The Windows sources use explicit int64_t/uint64_t instead of the INT64 macro
# and long*, which matters because long is 32-bit on MSVC.
kernel_dir = "lib/custom_rasterizer_kernel_for_windows" if sys.platform == "win32" else "lib/custom_rasterizer_kernel"

# torch guards an if-constexpr chain in csrc/dynamo/compiled_autograd.h behind
# _WIN32 && USE_CUDA because it miscompiles on MSVC ("'std': ambiguous symbol"),
# but cpp_extension never defines USE_CUDA, so define it here.
extra_compile_args = {"cxx": ["-DUSE_CUDA"], "nvcc": ["-DUSE_CUDA"]} if sys.platform == "win32" else {}

custom_rasterizer_module = CUDAExtension(
    "custom_rasterizer_kernel",
    [
        f"{kernel_dir}/rasterizer.cpp",
        f"{kernel_dir}/grid_neighbor.cpp",
        f"{kernel_dir}/rasterizer_gpu.cu",
    ],
    extra_compile_args=extra_compile_args,
)

setup(
    packages=find_packages(),
    version="0.1",
    name="custom_rasterizer",
    include_package_data=True,
    package_dir={"": "."},
    ext_modules=[
        custom_rasterizer_module,
    ],
    cmdclass={"build_ext": BuildExtension},
)
