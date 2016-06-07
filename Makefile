all:	targ

targ:	model.cu
	nvcc model.cu -o render -lIL -lGL -lglut -lGLEW -lassimp `pkg-config --cflags --libs opencv`

clean:
	rm -f render
