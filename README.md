Render 3D model from different viewpoints

nvcc render.c -o test -lGL -lGLU -lassimp -lglut `pkg-config --cflags --libs opencv`

./test
