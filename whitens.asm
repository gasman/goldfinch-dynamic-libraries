XLIB whitens
LIB border_entry

.whitens
	ld hl,0x0000
	ld de,0x4000
	ld bc,0x1000
	ldir
	jp border_entry
	