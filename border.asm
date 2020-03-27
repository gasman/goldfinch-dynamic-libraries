XLIB border
XDEF border_entry

.border
.border_entry
	xor a
.loop
	out (0xfe),a
	inc a
	and 0x07
	jp loop
