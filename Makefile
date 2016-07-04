all:	targ

targ:	render.cpp
	g++ render.cpp -o render -lIL -lGL -lglut -lGLEW -lassimp -lopencv_core -lopencv_highgui

clean:
	rm -f render
