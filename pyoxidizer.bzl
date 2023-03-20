# Below packages are using __file__ and need to be placed into a lib directory.
PACKAGES_TO_ADD = [
    "boto3",
    "boto",
    "git",
    "gitdb",
    "googleapiclient",
    "httplib2",
    "idlelib",
    "jinja2",
    "jsonschema",
]

def handle_resource(policy, resource):
    # Based on solution from https://github.com/indygreg/PyOxidizer/issues/436#issuecomment-939408632
    # and https://pyoxidizer.readthedocs.io/en/stable/pyoxidizer_packaging_resources.html#using-callbacks-to-influence-resource-attributes
    name = ""
    if type(resource) in ("PythonPackageResource", "PythonPackageDistributionResource"):
        name = resource.package
    elif type(resource) == "PythonModuleSource":
        name = resource.name
    elif type(resource) == "File":
        name = resource.path

    if any([True for pkg in PACKAGES_TO_ADD if pkg in name]):
        resource.add_location = "filesystem-relative:lib"
    else:
        resource.add_location = "in-memory"

def make_dist():
    return default_python_distribution( python_version = "3.9" )

def make_packaging_policy(dist):
    policy = dist.make_python_packaging_policy()

    # Register a function to be called when resources are created.
    policy.register_resource_callback(handle_resource)
    
    # Controls whether `File` instances are emitted by the file scanner.
    policy.file_scanner_emit_files = True

    # Try to add resources to in-memory first. If that fails, add them to a
    # "lib" directory relative to the built executable.
    policy.resources_location = "in-memory"
    policy.resources_location_fallback = "filesystem-relative:lib"

    # Enable support for non-classified "file" resources to be added to
    # resource collections.
    policy.allow_files = True

    # Controls the `add_include` attribute of `File` resources.
    policy.include_file_resources = False

    # Toggle whether Python module source code for modules in the Python
    # distribution's standard library are included.
    policy.include_distribution_sources = True

    # Controls the `add_include` attribute of `PythonModuleSource` not in
    # the standard library.
    policy.include_non_distribution_sources = True

    # # Toggle whether files associated with tests are included.
    policy.include_test = False
    
    return policy

def make_config(dist):
    python_config = dist.make_python_interpreter_config()

    # Set initial value for `sys.path`. If the string `$ORIGIN` exists in
    # a value, it will be expanded to the directory of the built executable.
    python_config.module_search_paths = ["$ORIGIN/lib"]

    # Enable the stdlib path-based importer.
    python_config.filesystem_importer = True
    
    # Evaluate a string as Python code when the interpreter starts.
    python_config.run_command = "import kapitan.cli; kapitan.cli.main()"

    return python_config

def make_exe(dist, policy, config):
    # Produce a PythonExecutable from a Python distribution, embedded
    # resources, and other options. The returned object represents the
    # standalone executable that will be built.
    exe = dist.to_python_executable(
        name="kapitan",
        packaging_policy=policy,
        config=config,
    )

    # Invoke `pip install` using a requirements file and add the collected resources
    # to our binary.
    exe.add_python_resources(exe.pip_install(["-r", "requirements.txt"]))

    # Read Python files from a local directory and add them to our embedded
    # context, taking just the resources belonging to the `foo` and `bar`
    # Python packages.
    exe.add_python_resources(exe.read_package_root(
        path=".",
        packages=["kapitan"],
    ))
    exe.add_python_resources(exe.read_package_root(
        path="kapitan/reclass",
        packages=["reclass"],
    ))

    return exe

def make_embedded_resources(exe):
    return exe.to_embedded_resources()

def make_install(exe, resources):
    files = FileManifest()
    files.add_python_resource(".", exe)

    return files

register_target("dist", make_dist)
register_target("policy", make_packaging_policy, depends=["dist"])
register_target("config", make_config, depends=["dist"])
register_target("exe", make_exe, depends=["dist", "policy", "config"])
register_target("resources", make_embedded_resources, depends=["exe"], default_build_script=True)
register_target("install", make_install, depends=["exe", "resources"], default=True)

resolve_targets()
