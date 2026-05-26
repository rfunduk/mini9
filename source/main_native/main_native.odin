package main_native

import "core:flags"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

import engine ".."

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

VERSION :: #load("../../VERSION", string)

Args :: struct {
	command:     string `args:"pos=0" usage:"command (package), or game file path"`,
	source:      string `args:"name=source,name=s" usage:"source directory for packaging"`,
	output:      string `args:"name=output,name=o" usage:"output file path for packaging"`,
	no_compress: bool `args:"name=no-compress" usage:"disable cart compression"`,
	web:         bool `args:"name=web" usage:"create web build with embedded assets"`,
	log_level:   string `args:"name=log-level" usage:"engine log level: debug, info, warn, error (default: warn release / debug debug-build)"`,
	version:     bool `args:"name=version" usage:"print version and exit"`,
}

main :: proc() {
	default_allocator := context.allocator

	when USE_TRACKING_ALLOCATOR {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		// `when` is compile-time only, so this defer is scoped to main()
		// and fires on every exit path — including the early `return` from
		// the `package` command, which previously bypassed the leak dump
		// entirely (silently masking allocations in packager.odin).
		defer {
			for _, value in tracking_allocator.allocation_map {
				log.errorf("%v: Leaked %v bytes", value.location, value.size)
			}
			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	args: Args
	parse_error := flags.parse(&args, os.args[1:], .Unix)
	if parse_error != nil {
		flags.print_errors(Args, parse_error, os.args[0], .Unix)
		os.exit(1)
	}

	if args.version {
		fmt.println(strings.trim_space(VERSION))
		os.exit(0)
	}

	level, level_ok := engine.resolve_log_level(args.log_level)
	if !level_ok {
		fmt.eprintfln("unknown --log-level: %q (expected debug, info, warn, error, fatal)", args.log_level)
		os.exit(1)
	}
	context.logger = log.create_console_logger(
		level,
		{.Level, .Date, .Time, .Terminal_Color},
		allocator = default_allocator,
	)

	// check if this is a packaging command
	if args.command == "package" {
		packager(&args)
		return
	}

	rom_data: ^engine.Rom_Data = nil

	// check if command is a path to a cart file
	if len(args.command) > 0 {
		if os.is_dir(args.command) {
			os.chdir(args.command)
		} else if os.exists(args.command) {
			rom_data = engine.get_rom_data(args.command)
		}
	}
	engine.engine_init(rom_data, args.command)

	for engine.engine_is_running() {
		engine.engine_update()

		when USE_TRACKING_ALLOCATOR {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			clear(&tracking_allocator.bad_free_array)
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	engine.engine_shutdown()
	engine.engine_shutdown_window()
}


// make game use good GPU on laptops etc

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
