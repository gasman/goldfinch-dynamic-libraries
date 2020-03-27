all:
	z80asm border.asm
	z80asm whitens.asm
	ruby dog/dog.rb border.obj border.dog
	ruby dog/dog.rb -i border.obj whitens.obj whitens.dog
	hdfmonkey put testfat.hdf border.dog /lib/border.dog
	hdfmonkey put testfat.hdf whitens.dog /lib/whitens.dog
	pasmo dyload.asm dyload.bin
	hdfmonkey put testfat.hdf dyload.bin /bin/dyload
	