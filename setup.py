import sys
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext

class CustomBuildExt(build_ext):
    """
    A custom build_ext command that adds extra flags
    based on the detected compiler.
    """
    def build_extensions(self):
        compiler_type = self.compiler.compiler_type

        for ext in self.extensions:
            # Ensure RTTI is enabled
            ext.extra_compile_args = ext.extra_compile_args or []
            ext.extra_compile_args.append("-frtti")

            # Add additional warning flags for Unix compilers
            if compiler_type == "unix":
                # Check the actual compiler name (gcc vs. clang)
                compiler = self.compiler.compiler[0]
                if "clang" in compiler:
                    ext.extra_compile_args.extend(["-Wall", "-Wextra"])
                elif "gcc" in compiler:
                    ext.extra_compile_args.extend([
                        "-Wall", "-Wextra", "-Wpedantic", "-Wconversion", "-Wsign-conversion",
                        "-Wcast-qual", "-Wformat=2", "-Wundef", "-Werror=float-equal", "-Wshadow",
                        "-Wcast-align", "-Wunused", "-Wnull-dereference", "-Wdouble-promotion",
                        "-Wimplicit-fallthrough", "-Wextra-semi", "-Woverloaded-virtual", "-Wnon-virtual-dtor",
                    ])

        build_ext.build_extensions(self)

# Define the SWIG extension.
buffer_extension = Extension(
    name="buffer_interface",
    sources=["src/buffer_interface.i"],  # SWIG will generate the C++ wrapper
    swig_opts=["-c++", "-threads", "-Wextra", "-Wall"],
    define_macros=[("Py_LIMITED_API", "0x03090000")],
    include_dirs=["src"],  # so that SWIG can find your headers if needed
    extra_compile_args=[],  # flags will be added in CustomBuildExt
)

setup(
    name="BufferTest",
    version="0.1",
    description="Python extension module compiled with SWIG",
    ext_modules=[buffer_extension],
    cmdclass={"build_ext": CustomBuildExt},
    # Setup test configuration to run pytest
    tests_require=["pytest"],
    setup_requires=["pytest-runner"],
    classifiers=[
        "Programming Language :: Python",
        "Programming Language :: C++",
    ],
)
