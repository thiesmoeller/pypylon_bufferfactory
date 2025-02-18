import sys
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext

buffer_extension = Extension(
    name="buffer_interface",
    sources=["src/buffer_interface.i"],
    swig_opts=["-c++", "-threads", "-Wextra", "-Wall"],
    define_macros=[("Py_LIMITED_API", "0x03090000")],
    include_dirs=["src"],
    extra_compile_args=[],  # Compiler flags added in your custom build_ext.
    py_limited_api=True,     # This tells setuptools to build an "abi3" wheel.
)

setup(
    name="BufferTest",
    version="0.1",
    description="Python extension module compiled with SWIG using the limited API (Python >= 3.9)",
    ext_modules=[buffer_extension],
    python_requires=">=3.9",
    tests_require=["pytest"],
    setup_requires=["pytest-runner"],
    classifiers=[
        "Programming Language :: Python",
        "Programming Language :: C++",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
    ],
)
