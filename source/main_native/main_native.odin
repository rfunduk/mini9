package main_native

import "core:flags"
import "core:log"
import "core:os"
import "core:strings"

import engine ".."

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

Args :: struct {
	command:     string `args:"pos=0" usage:"command (package), or game file path"`,
	source:      string `args:"name=source,name=s" usage:"source directory for packaging"`,
	output:      string `args:"name=output,name=o" usage:"output file path for packaging"`,
	no_compress: bool `args:"name=no-compress" usage:"disable ROM compression"`,
	web:         bool `args:"name=web" usage:"create web build with embedded assets"`,
}

main :: proc() {
	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		tracking_allocator: Tracking_Allocator
		tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = allocator_from_tracking_allocator(&tracking_allocator)
	}

	context.logger = log.create_console_logger(.Debug, {.Level, .Date, .Time, .Terminal_Color})

	args: Args
	parse_error := flags.parse(&args, os.args[1:], .Unix)
	if parse_error != nil {
		flags.print_errors(Args, parse_error, os.args[0], .Unix)
		os.exit(1)
	}

	// check if this is a packaging command
	if args.command == "package" {
		rom_data := packager(&args)
		return
	}

	rom_data: ^engine.Rom_Data = nil

	// check if command is a path to a ROM file
	if len(args.command) > 0 {
		if os.is_dir(args.command) {
			os.set_current_directory(args.command)
		} else if os.exists(args.command) {
			rom_data = engine.get_rom_data(args.command)
		}
	}
	engine.engine_init(rom_data)

	for engine.engine_is_running() {
		engine.engine_update()

		when USE_TRACKING_ALLOCATOR {
			for b in tracking_allocator.bad_free_array {
				log.error("Bad free at: %v", b.location)
			}

			clear(&tracking_allocator.bad_free_array)
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	engine.engine_shutdown()
	engine.engine_shutdown_window()

	when USE_TRACKING_ALLOCATOR {
		for key, value in tracking_allocator.allocation_map {
			log.error("%v: Leaked %v bytes\n", value.location, value.size)
		}

		tracking_allocator_destroy(&tracking_allocator)
	}
}


// make game use good GPU on laptops etc

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
