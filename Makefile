all:	targ

targ:	render.cu
	nvcc render.cu -o render -lIL -lGL -lglut -lGLEW -lassimp `pkg-config --cflags --libs opencv`

clean:
	rm -f render
