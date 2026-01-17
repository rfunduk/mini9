#+build !wasm32
#+build !wasm64p32

package engine

// embed web build assets at compile time
web_index_html := #load("../build/web/index.html")
web_index_js := #load("../build/web/index.js")
web_index_wasm := #load("../build/web/index.wasm")
web_odin_js := #load("../build/web/odin.js")

Web_Asset :: struct {
	name: string,
	data: []u8,
}

// web assets registry
web_assets := [4]Web_Asset {
	{"index.html", web_index_html},
	{"index.js", web_index_js},
	{"index.wasm", web_index_wasm},
	{"odin.js", web_odin_js},
}
