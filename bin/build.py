#!/usr/bin/env python3

from os import path, environ
from sys import exit
from subprocess import run
from pathlib import Path
from argparse import ArgumentParser
from glob import glob
from re import findall
from hashlib import file_digest


parser = ArgumentParser()
parser.add_argument(
    "target",
    nargs="?",
    default="release",
    choices=["debug", "release"],
)
args = parser.parse_args()


SRC_DIR = path.abspath("./source")


def build_tools():
    tools = [Path(tool) for tool in glob("bin/*.odin")]
    for tool in tools:
        print(f"  {tool.stem}", end="", flush=True)
        result = run(
            [
                "odin",
                "build",
                tool,
                "-file",
                f"-out:bin/__{tool.stem}__generated",
                "-collection:lib=lib",
                "-define:MRUBY_LIB=../../vendor/mruby/build/host/lib/libmruby.a",
                "-strict-style",
                "-vet",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise ValueError(
                f"Unable to generate bytecode -- {result.stdout} {result.stderr}"
            )
        print("\tOK")


def generate_step():
    # scan native engine subsystems for api methods
    engine_methods = scan_engine_methods()

    # add engine method registration to ruby_api
    with open(path.join(SRC_DIR, "../ruby_api/auto__generated.rb"), "w") as f:
        f.write("ENGINE_METHODS = [")
        for m, _, _ in engine_methods:
            f.write(f"'{m}',")
        f.write("]\n")

    # scan for all ruby_api .rb files
    ruby_files_to_load = build_ruby_api()

    # generate the init file
    init_content = []
    init_content.append("package engine")
    init_content.append('import rl "vendor:raylib"')
    init_content.append('import mrb "lib:mruby"')

    init_content.append("")
    for api_name, type, (native, ruby) in ruby_files_to_load:
        name = api_name.strip("_")
        init_content.append(
            f'{name}_bytecode := #load("../ruby_api/{name}__generated.bin")'
        )
    init_content.append("")

    # generate *_Ruby `mrb_data_type`s
    for api_name, type, (native, ruby) in ruby_files_to_load:
        if type == "init" and native and ruby:
            init_content.append(
                f"{ruby}_Ruby := mrb.Data_Type {{ "
                f'struct_name = "{ruby}", '
                f"dfree = ruby_{ruby.lower()}_finalizer }}"
            )

    init_content.append("")
    init_content.append("engine_init_ruby_api :: proc() {")
    init_content.append("\tNATIVE_TO_MRUBY_TYPE = make(map[typeid]^mrb.Data_Type)")

    # add NATIVE_TO_MRUBY_TYPE defns
    for _, type, (native, ruby) in ruby_files_to_load:
        if type == "init" and native and ruby:
            init_content.append(f"\tNATIVE_TO_MRUBY_TYPE[{native}] = &{ruby}_Ruby")

    init_content.append("")

    # add built-in api methods
    init_content.append('\tkernel_module := mrb.module_get(g.mrb_state, "Kernel")')
    for name, f, arity in engine_methods:
        init_content.append(
            f'\tmrb.define_method(g.mrb_state, kernel_module, "{name}", cast(rawptr){f}, {arity})'
        )

    # load bytecode and init subsystems
    for api_name, type, (native, ruby) in ruby_files_to_load:
        init_content.append(f"\n\t// {api_name}")
        init_content.append(
            f'\tload_bytecode("{api_name}", {api_name.strip("_")}_bytecode[:])'
        )
        if type == "init":
            init_content.append(f"\tsetup_{api_name}()")

    init_content.append("}")

    # write the generated odin module
    print("  Generating engine_ruby_api__generated.odin...", flush=True)
    init_file_path = path.join(SRC_DIR, "engine_ruby_api__generated.odin")
    with open(init_file_path, "w") as f:
        f.write("\n".join(init_content) + "\n")


def build_ruby_api():
    ruby_api_dir = path.join(SRC_DIR, "../ruby_api")
    ruby_files = glob(path.join(ruby_api_dir, "*.rb"))

    to_load = []

    for ruby_file in ruby_files:
        auto = "load"
        api_name = Path(ruby_file).stem

        native = None
        ruby = None
        with open(ruby_file, "r") as f:
            lines = f.readlines()
            if len(lines) == 0:
                continue
            m = findall(
                r"^# ENGINE native=([.a-zA-Z0-9_]+) ruby=([.a-zA-Z0-9_]+)",
                lines[0],
            )

            if m:
                native, ruby = m[0]

        print(f"  Generating bytecode for {api_name}...", flush=True)

        # check if corresponding .odin file exists with `setup_{api_name}` function
        odin_file = path.join(SRC_DIR, f"engine_{api_name}.odin")
        if path.exists(odin_file):
            with open(odin_file, "r") as f:
                odin_content = f.read()
                if f"setup_{api_name} ::" in odin_content:
                    # if it does then we want to not only load the bytecode,
                    # but also call the setup function during engine init
                    auto = "init"

        convert_cmd = [
            "bin/__rb2bin__generated",
            f"ruby_api/{api_name}.rb",
            f"ruby_api/{api_name.strip('_')}__generated.bin",
        ]
        if args.target == "debug":
            convert_cmd.append("--debug")
        result = run(convert_cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise ValueError(
                f"Unable to generate bytecode -- {result.stdout} {result.stderr}"
            )
        else:
            to_load.append((api_name, auto, (native, ruby)))

    to_load.sort()
    return to_load


def scan_engine_methods():
    # scan for @engine_method annotated functions
    print("  Scanning for @engine_method functions...", flush=True)
    engine_methods = []
    odin_files = glob(path.join(SRC_DIR, "*.odin"))

    for odin_file in odin_files:
        with open(odin_file, "r") as f:
            # find all @engine_method comments with the function on the next line
            # pattern: // @engine_method: name="method_name", arity=N
            lines = f.read().split("\n")
            for i, line in enumerate(lines):
                if "@engine_method:" not in line:
                    continue

                name_match = findall(r'name="([^"]+)"', line)
                arity_match = findall(r"arity=(-?\d+)", line)

                if name_match and arity_match and i + 1 < len(lines):
                    method_name = name_match[0]
                    arity = int(arity_match[0])

                    # extract the function name from the next line
                    next_line = lines[i + 1]
                    func_match = findall(r'(\w+)\s*::\s*proc\s*"c"', next_line)
                    if func_match:
                        func_name = func_match[0]
                        engine_methods.append((method_name, func_name, arity))

    return engine_methods


def maybe_build_tools():
    prev_digest_path = "bin/__rb2bin__generated.digest"
    prev_digest = None
    if path.isfile(prev_digest_path):
        with open(prev_digest_path, "r") as f:
            prev_digest = f.read()

    current_digest = None
    with open("bin/rb2bin.odin", "rb", buffering=0) as f:
        current_digest = file_digest(f, "sha256").hexdigest()

    if prev_digest is None or prev_digest != current_digest:
        print("Re-building tools...", end="\n")
        build_tools()
        print("")
        with open(prev_digest_path, "w") as f:
            f.write(current_digest)


if __name__ == "__main__":
    # ensure we have rb2bin built
    maybe_build_tools()

    print(f"Preparing '{args.target}'...")

    # remove existing build
    run(["rm", "-rf", path.abspath(f"./build/{args.target}")])

    # generate engine code/ruby api/etc
    generate_step()

    print(f"Building '{args.target}'...")
    result = run("bin/_build.sh", env=environ.update({"TARGET": args.target}))
    if result.returncode != 0:
        print(f"Build failed with exit code {result.returncode}")
        exit(result.returncode)

    print("Build complete.")
