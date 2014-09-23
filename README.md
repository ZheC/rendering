Render 3D model from different viewpoints

nvcc model.cu -o test -lIL -lGL -lglut -lGLEW -lassimp `pkg-config --cflags --libs opencv`

./test
