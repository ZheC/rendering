all:	targ

targ:	model.cu
	nvcc model.cu -o test -lIL -lGL -lglut -lGLEW -lassimp `pkg-config --cflags --libs opencv`

clean:
	rm -f test
