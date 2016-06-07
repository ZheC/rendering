# Render 3D model from different viewpoints #

nvcc model.cu -o test -lIL -lGL -lglut -lGLEW -lassimp `pkg-config --cflags --libs opencv`

./test

# Structure of the program #

main calls glutDisplayFunc w/ renderScene as an argument, then glutReshapeFunc w/ changeSize as an argument 

renderScene is what renders the model and saves the images to the ./output directory  

renderScene first calls setCamera (where the camera is & what it's looking), then scales and rotates the object, etc.  

changeSize calls buildProjectionMatrix...; buildProjectionMatrix is what has fov, ratio, nearp, and farp  

# Structure of the input data #

input/ directory should have vertex (.vert), fragment (.frag), and model (.obj) files

# Structure of the output data #

output/ directory has the renders