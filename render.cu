// -*- mode: c++ -*-

// Produce renders of CAD model

// include DevIL for image loading
#include <IL/il.h>
// auxiliary C file to read the shader text files
#include "textfile.h"
// assimp
#include "assimp/Importer.hpp"	
#include "assimp/postprocess.h"
#include "assimp/scene.h"
//opencv
#include "cv.h"
#include "highgui.h"

#include <GL/glew.h>
#include <GL/freeglut.h>
#include <math.h>
#include <fstream>
#include <map>
#include <string>
#include <vector>

char gvar_vertex_fname[256];
char gvar_fragment_fname[256];
char gvar_model_fname[256];

float gvar_delta_rot_x, gvar_delta_rot_y, gvar_delta_rot_z;
int gvar_num_rot_x, gvar_num_rot_y, gvar_num_rot_z;

float gvar_proj_mtx_horiz_fov;
float gvar_proj_mtx_near_clip_plane, gvar_proj_mtx_far_clip_plane;
int gvar_render_size_width, gvar_render_size_height;

/// params for model -- default values below, can be overridden
#define MODEL_FILENAME "./input/17_Pet_bottle_pet_tea.ply"
//#define MODEL_FILENAME "./input/19_Dish_bawl_rice.ply"
//#define MODEL_FILENAME "./input/14_MugCup_green.ply"
//#define MODEL_FILENAME "./input/arc.obj" // this can be OBJ or PLY (may be others work as well)

#define VERTEX_FILENAME "./input/with_texture.vert" // these have to do w/ shading, etc. (not the actual object); more details here: http://stackoverflow.com/questions/6432838/what-is-the-correct-file-extension-for-glsl-shaders
#define FRAGMENT_FILENAME "./input/with_texture.frag"

/// params for render angles -- default values below, can be overridden
#define DELTA_ROT_X 20 // deg.
#define DELTA_ROT_Y 20 // deg.
#define DELTA_ROT_Z 10 // deg.
#define NUM_ROT_X 2 // in increments of DELTA_ROT_X
#define NUM_ROT_Y 3 // in increments of DELTA_ROT_Y
#define NUM_ROT_Z 36 // in increments of DELTA_ROT_Z

/// params for projection matrix, image size, etc. in renders (more details on the whole process of rendering here: http://www.opengl-tutorial.org/beginners-tutorials/tutorial-3-matrices/)
// FOV and RENDER_SIZE basically make up the camera focal length (radial distortion probably not bothered with)
#define PROJ_MTX_HORIZONTAL_FOV 20.0f // as the FOV increases (or decreases), the object is further from (or closer to) the camera
#define PROJ_MTX_NEAR_CLIP_PLANE 0.1f
#define PROJ_MTX_FAR_CLIP_PLANE 100.0f
#define RENDER_SIZE_WIDTH 180
#define RENDER_SIZE_HEIGHT RENDER_SIZE_WIDTH 

aiVector3D scene_min, scene_max, scene_center;

/// Information to render each assimp node
struct MyMesh{

  GLuint vao;
  GLuint texIndex;
  GLuint uniformBlockIndex;
  int numFaces;
};

///
std::vector<struct MyMesh> myMeshes;

/// This is for a shader uniform block
struct MyMaterial{

  float diffuse[4];
  float ambient[4];
  float specular[4];
  float emissive[4];
  float shininess;
  int texCount;
};

/// Model Matrix (part of the OpenGL Model View Matrix)
float modelMatrix[16];

/// For push and pop matrix
std::vector<float *> matrixStack;

/// Vertex Attribute Locations
GLuint vertexLoc=0, normalLoc=1, texCoordLoc=2;

/// Uniform Bindings Points
GLuint matricesUniLoc = 1, materialUniLoc = 2;

/// The sampler uniform for textured models
// we are assuming a single texture so this will
//always be texture unit 0
GLuint texUnit = 0;

/// Uniform Buffer for Matrices
// this buffer will contain 3 matrices: projection, view and model
// each matrix is a float array with 16 components
GLuint matricesUniBuffer;
#define MatricesUniBufferSize sizeof(float) * 16 * 3
#define ProjMatrixOffset 0
#define ViewMatrixOffset sizeof(float) * 16
#define ModelMatrixOffset sizeof(float) * 16 * 2
#define MatrixSize sizeof(float) * 16

/// Program and Shader Identifiers
GLuint program, vertexShader, fragmentShader;

// Shader Names
//char *vertexFileName = "dirlightdiffambpix.vert";
//char *fragmentFileName = "dirlightdiffambpix.frag";
//char *vertexFileName = "with_texture.vert";
//char *fragmentFileName = "with_texture.frag";

/// Create an instance of the Importer class
Assimp::Importer importer;

/// the global Assimp scene object
const aiScene* scene = NULL;

/// scale factor for the model to fit in the window
float scaleFactor;

/// images / texture
// map image filenames to textureIds pointer to texture Array
std::map<std::string, GLuint> textureIdMap;	

// Replace the model name by your model's filename
//static const std::string modelname = "arc.obj";

/// Camera Position
/// @warning why is camZ fixed?
float camX = 0, camY = 0, camZ = 5;

/// Mouse Tracking Variables
int startX, startY, tracking = 0;

/// Camera Spherical Coordinates
float alpha = 0.0f, beta = 0.0f;
float r = 5.0f;

///
static inline float 
DegToRad(float degrees) 
{ 
  return (float)(degrees * (M_PI / 180.0f));
};

// ----------------------------------------------------
// VECTOR STUFF

/// res = a cross b;
void crossProduct( float *a, float *b, float *res) {
  res[0] = a[1] * b[2]  -  b[1] * a[2];
  res[1] = a[2] * b[0]  -  b[2] * a[0];
  res[2] = a[0] * b[1]  -  b[0] * a[1];
}

/// Normalize a vec3
void normalize(float *a) {
  float mag = sqrt(a[0] * a[0]  +  a[1] * a[1]  +  a[2] * a[2]);
  a[0] /= mag;
  a[1] /= mag;
  a[2] /= mag;
}

// ----------------------------------------------------
// MATRIX STUFF

/// Push for modelMatrix
void pushMatrix() {

  float *aux = (float *)malloc(sizeof(float) * 16);
  memcpy(aux, modelMatrix, sizeof(float) * 16);
  matrixStack.push_back(aux);
}

/// Pop for modelMatrix
void popMatrix() {

  float *m = matrixStack[matrixStack.size()-1];
  memcpy(modelMatrix, m, sizeof(float) * 16);
  matrixStack.pop_back();
  free(m);
}

/// sets the square matrix mat to the identity matrix,
// size refers to the number of rows (or columns)
void setIdentityMatrix( float *mat, int size) {

  // fill matrix with 0s
  for (int i = 0; i < size * size; ++i)
    mat[i] = 0.0f;

  // fill diagonal with 1s
  for (int i = 0; i < size; ++i)
    mat[i + i * size] = 1.0f;
}

/// a = a * b;
void multMatrix(float *a, float *b) {

  float res[16];

  for (int i = 0; i < 4; ++i) {
    for (int j = 0; j < 4; ++j) {
      res[j*4 + i] = 0.0f;
      for (int k = 0; k < 4; ++k) {
	res[j*4 + i] += a[k*4 + i] * b[j*4 + k]; 
      }
    }
  }
  memcpy(a, res, 16 * sizeof(float));
}

/// Defines a transformation matrix mat with a translation
void setTranslationMatrix(float *mat, float x, float y, float z) {

  setIdentityMatrix(mat,4);
  mat[12] = x;
  mat[13] = y;
  mat[14] = z;
}

/// Defines a transformation matrix mat with a scale
void setScaleMatrix(float *mat, float sx, float sy, float sz) {

  setIdentityMatrix(mat,4);
  mat[0] = sx;
  mat[5] = sy;
  mat[10] = sz;
}

/// Defines a transformation matrix mat with a rotation 
// angle alpha and a rotation axis (x,y,z)
void setRotationMatrix(float *mat, float angle, float x, float y, float z) {

  float radAngle = DegToRad(angle);
  float co = cos(radAngle);
  float si = sin(radAngle);
  float x2 = x*x;
  float y2 = y*y;
  float z2 = z*z;

  mat[0] = x2 + (y2 + z2) * co; 
  mat[4] = x * y * (1 - co) - z * si;
  mat[8] = x * z * (1 - co) + y * si;
  mat[12]= 0.0f;
	   
  mat[1] = x * y * (1 - co) + z * si;
  mat[5] = y2 + (x2 + z2) * co;
  mat[9] = y * z * (1 - co) - x * si;
  mat[13]= 0.0f;
	   
  mat[2] = x * z * (1 - co) - y * si;
  mat[6] = y * z * (1 - co) + x * si;
  mat[10]= z2 + (x2 + y2) * co;
  mat[14]= 0.0f;
	   
  mat[3] = 0.0f;
  mat[7] = 0.0f;
  mat[11]= 0.0f;
  mat[15]= 1.0f;
}

// ----------------------------------------------------
/// Model Matrix 

/// Copies the modelMatrix to the uniform buffer
void setModelMatrix() {
  glBindBuffer(GL_UNIFORM_BUFFER,matricesUniBuffer);
  glBufferSubData(GL_UNIFORM_BUFFER,ModelMatrixOffset, MatrixSize, modelMatrix);
  glBindBuffer(GL_UNIFORM_BUFFER,0);
}

/// The equivalent to glTranslate applied to the model matrix
void translate(float x, float y, float z) {
  float aux[16];
  setTranslationMatrix(aux,x,y,z);
  multMatrix(modelMatrix,aux);
  setModelMatrix();
}

/// The equivalent to glRotate applied to the model matrix
void rotate(float angle, float x, float y, float z) {
  float aux[16];
  setRotationMatrix(aux,angle,x,y,z);
  multMatrix(modelMatrix,aux);
  setModelMatrix();
}

/// The equivalent to glScale applied to the model matrix
void scale(float x, float y, float z) {
  float aux[16];
  setScaleMatrix(aux,x,y,z);
  multMatrix(modelMatrix,aux);
  setModelMatrix();
}

// ----------------------------------------------------
/// Projection Matrix 

/// Computes the projection Matrix and stores it in the uniform buffer
void buildProjectionMatrix(float fov, float ratio, float nearp, float farp) {
  float projMatrix[16];
  float f = 1.0f / tan (fov * (M_PI / 360.0f));
  setIdentityMatrix(projMatrix,4);

  projMatrix[0] = f / ratio;
  projMatrix[1 * 4 + 1] = f;
  projMatrix[2 * 4 + 2] = (farp + nearp) / (nearp - farp);
  projMatrix[3 * 4 + 2] = (2.0f * farp * nearp) / (nearp - farp);
  projMatrix[2 * 4 + 3] = -1.0f;
  projMatrix[3 * 4 + 3] = 0.0f;

  glBindBuffer(GL_UNIFORM_BUFFER,matricesUniBuffer);
  glBufferSubData(GL_UNIFORM_BUFFER, ProjMatrixOffset, MatrixSize, projMatrix);
  glBindBuffer(GL_UNIFORM_BUFFER,0);

}

// ----------------------------------------------------
/// View Matrix

/// Computes the viewMatrix and stores it in the uniform buffer
void setCamera(float posX, float posY, float posZ, 
	       float lookAtX, float lookAtY, float lookAtZ) {

  float dir[3], right[3], up[3];
  up[0] = 0.0f;	up[1] = 1.0f;	up[2] = 0.0f;

  dir[0] =  (lookAtX - posX);
  dir[1] =  (lookAtY - posY);
  dir[2] =  (lookAtZ - posZ);
  normalize(dir);

  crossProduct(dir,up,right);
  normalize(right);

  crossProduct(right,dir,up);
  normalize(up);

  float viewMatrix[16],aux[16];

  viewMatrix[0]  = right[0];
  viewMatrix[4]  = right[1];
  viewMatrix[8]  = right[2];
  viewMatrix[12] = 0.0f;

  viewMatrix[1]  = up[0];
  viewMatrix[5]  = up[1];
  viewMatrix[9]  = up[2];
  viewMatrix[13] = 0.0f;

  viewMatrix[2]  = -dir[0];
  viewMatrix[6]  = -dir[1];
  viewMatrix[10] = -dir[2];
  viewMatrix[14] =  0.0f;

  viewMatrix[3]  = 0.0f;
  viewMatrix[7]  = 0.0f;
  viewMatrix[11] = 0.0f;
  viewMatrix[15] = 1.0f;

  setTranslationMatrix(aux, -posX, -posY, -posZ);

  multMatrix(viewMatrix, aux);
	
  glBindBuffer(GL_UNIFORM_BUFFER, matricesUniBuffer);
  glBufferSubData(GL_UNIFORM_BUFFER, ViewMatrixOffset, MatrixSize, viewMatrix);
  glBindBuffer(GL_UNIFORM_BUFFER,0);
}

// ----------------------------------------------------------------------------

#define aisgl_min(x,y) (x<y?x:y)
#define aisgl_max(x,y) (y>x?y:x)

///
void get_bounding_box_for_node (const aiNode* nd, 
				aiVector3D* min, 
				aiVector3D* max)
{
  aiMatrix4x4 prev;
  unsigned int n = 0, t;

  for (; n < nd->mNumMeshes; ++n) {
    const aiMesh* mesh = scene->mMeshes[nd->mMeshes[n]];
    for (t = 0; t < mesh->mNumVertices; ++t) {

      aiVector3D tmp = mesh->mVertices[t];

      min->x = aisgl_min(min->x,tmp.x);
      min->y = aisgl_min(min->y,tmp.y);
      min->z = aisgl_min(min->z,tmp.z);

      max->x = aisgl_max(max->x,tmp.x);
      max->y = aisgl_max(max->y,tmp.y);
      max->z = aisgl_max(max->z,tmp.z);
    }
  }

  for (n = 0; n < nd->mNumChildren; ++n) {
    get_bounding_box_for_node(nd->mChildren[n],min,max);
  }
}

///
void get_bounding_box (aiVector3D* min, aiVector3D* max)
{

  min->x = min->y = min->z =  1e10f;
  max->x = max->y = max->z = -1e10f;
  get_bounding_box_for_node(scene->mRootNode,min,max);
}

///
bool Import3DFromFile( const std::string& pFile)
{
  //check if file exists
  std::ifstream fin(pFile.c_str());
  if(!fin.fail()) {
    fin.close();
  }
  else{
    printf("Couldn't open file: %s\n", pFile.c_str());
    printf("%s\n", importer.GetErrorString());
    return false;
  }

  scene = importer.ReadFile( pFile, aiProcessPreset_TargetRealtime_Quality);

  // If the import failed, report it
  if( !scene)
    {
      printf("%s\n", importer.GetErrorString());
      return false;
    }

  printf("Import of scene %s succeeded\n",pFile.c_str());

  get_bounding_box(&scene_min, &scene_max);
  scene_center.x = (scene_min.x + scene_max.x) / 2.0f;
  scene_center.y = (scene_min.y + scene_max.y) / 2.0f;
  scene_center.z = (scene_min.z + scene_max.z) / 2.0f;
  printf("Scene center: %f, %f, %f\n", scene_center.x, scene_center.y, scene_center.z);
  //center the model
  glTranslatef( -scene_center.x, -scene_center.y, -scene_center.z );
  //translate( -scene_center.x, -scene_center.y, -1500 );
		
  float tmp;
  tmp = scene_max.x-scene_min.x;
  tmp = scene_max.y - scene_min.y > tmp?scene_max.y - scene_min.y:tmp;
  tmp = scene_max.z - scene_min.z > tmp?scene_max.z - scene_min.z:tmp;
  scaleFactor = 1.4f / tmp;

  return true;
}

///
int LoadGLTextures(const aiScene* scene)
{
  ILboolean success;

  /* initialization of DevIL */
  ilInit(); 

  /* scan scene's materials for textures */
  for (unsigned int m=0; m<scene->mNumMaterials; ++m)
    {
      int texIndex = 0;
      aiString path;	// filename

      aiReturn texFound = scene->mMaterials[m]->GetTexture(aiTextureType_DIFFUSE, texIndex, &path);
      while (texFound == AI_SUCCESS) {
	//fill map with textures, OpenGL image ids set to 0
	textureIdMap[path.data] = 0; 
	// more textures?
	texIndex++;
	texFound = scene->mMaterials[m]->GetTexture(aiTextureType_DIFFUSE, texIndex, &path);
      }
    }

  int numTextures = textureIdMap.size();

  /* create and fill array with DevIL texture ids */
  ILuint* imageIds = new ILuint[numTextures];
  ilGenImages(numTextures, imageIds); 

  /* create and fill array with GL texture ids */
  GLuint* textureIds = new GLuint[numTextures];
  glGenTextures(numTextures, textureIds); /* Texture name generation */

  /* get iterator */
  std::map<std::string, GLuint>::iterator itr = textureIdMap.begin();
  int i=0;
  for (; itr != textureIdMap.end(); ++i, ++itr)
    {
      //save IL image ID
      std::string filename = (*itr).first;  // get filename
      (*itr).second = textureIds[i];	  // save texture id for filename in map

      ilBindImage(imageIds[i]); /* Binding of DevIL image name */
      ilEnable(IL_ORIGIN_SET);
      ilOriginFunc(IL_ORIGIN_LOWER_LEFT); 
      success = ilLoadImage((ILstring)filename.c_str());

      if (success) {
	/* Convert image to RGBA */
	ilConvertImage(IL_RGBA, IL_UNSIGNED_BYTE); 

	/* Create and load textures to OpenGL */
	glBindTexture(GL_TEXTURE_2D, textureIds[i]); 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR); 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, ilGetInteger(IL_IMAGE_WIDTH),
		     ilGetInteger(IL_IMAGE_HEIGHT), 0, GL_RGBA, GL_UNSIGNED_BYTE,
		     ilGetData()); 
      }
      else 
	printf("Couldn't load Image: %s\n", filename.c_str());
    }

  ilDeleteImages(numTextures, imageIds); 

  //Cleanup
  delete [] imageIds;
  delete [] textureIds;

  //return success;
  return true;
}

///
void set_float4(float f[4], float a, float b, float c, float d)
{
  f[0] = a;
  f[1] = b;
  f[2] = c;
  f[3] = d;
}

///
void color4_to_float4(const aiColor4D *c, float f[4])
{
  f[0] = c->r;
  f[1] = c->g;
  f[2] = c->b;
  f[3] = c->a;
}

///
void genVAOsAndUniformBuffer(const aiScene *sc) {

  struct MyMesh aMesh;
  struct MyMaterial aMat; 
  GLuint buffer;
	
  // For each mesh
  for (unsigned int n = 0; n < sc->mNumMeshes; ++n)
    {
      const aiMesh* mesh = sc->mMeshes[n];

      // create array with faces
      // have to convert from Assimp format to array
      unsigned int *faceArray;
      faceArray = (unsigned int *)malloc(sizeof(unsigned int) * mesh->mNumFaces * 3);
      unsigned int faceIndex = 0;

      for (unsigned int t = 0; t < mesh->mNumFaces; ++t) {
	const aiFace* face = &mesh->mFaces[t];

	memcpy(&faceArray[faceIndex], face->mIndices,3 * sizeof(unsigned int));
	faceIndex += 3;
      }
      aMesh.numFaces = sc->mMeshes[n]->mNumFaces;

      // generate Vertex Array for mesh
      glGenVertexArrays(1,&(aMesh.vao));
      glBindVertexArray(aMesh.vao);

      // buffer for faces
      glGenBuffers(1, &buffer);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(unsigned int) * mesh->mNumFaces * 3, faceArray, GL_STATIC_DRAW);

      // buffer for vertex positions
      if (mesh->HasPositions()) {
	glGenBuffers(1, &buffer);
	glBindBuffer(GL_ARRAY_BUFFER, buffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(float)*3*mesh->mNumVertices, mesh->mVertices, GL_STATIC_DRAW);
	glEnableVertexAttribArray(vertexLoc);
	glVertexAttribPointer(vertexLoc, 3, GL_FLOAT, 0, 0, 0);
      }

      // buffer for vertex normals
      if (mesh->HasNormals()) {
	glGenBuffers(1, &buffer);
	glBindBuffer(GL_ARRAY_BUFFER, buffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(float)*3*mesh->mNumVertices, mesh->mNormals, GL_STATIC_DRAW);
	glEnableVertexAttribArray(normalLoc);
	glVertexAttribPointer(normalLoc, 3, GL_FLOAT, 0, 0, 0);
      }

      // buffer for vertex texture coordinates
      if (mesh->HasTextureCoords(0)) {
	float *texCoords = (float *)malloc(sizeof(float)*2*mesh->mNumVertices);
	for (unsigned int k = 0; k < mesh->mNumVertices; ++k) {

	  texCoords[k*2]   = mesh->mTextureCoords[0][k].x;
	  texCoords[k*2+1] = mesh->mTextureCoords[0][k].y; 
				
	}
	glGenBuffers(1, &buffer);
	glBindBuffer(GL_ARRAY_BUFFER, buffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(float)*2*mesh->mNumVertices, texCoords, GL_STATIC_DRAW);
	glEnableVertexAttribArray(texCoordLoc);
	glVertexAttribPointer(texCoordLoc, 2, GL_FLOAT, 0, 0, 0);
      }

      // unbind buffers
      glBindVertexArray(0);
      glBindBuffer(GL_ARRAY_BUFFER,0);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,0);
	
      // create material uniform buffer
      aiMaterial *mtl = sc->mMaterials[mesh->mMaterialIndex];
			
      aiString texPath;	//contains filename of texture
      if(AI_SUCCESS == mtl->GetTexture(aiTextureType_DIFFUSE, 0, &texPath)){
	//bind texture
	unsigned int texId = textureIdMap[texPath.data];
	aMesh.texIndex = texId;
	aMat.texCount = 1;
      }
      else
	aMat.texCount = 0;

      float c[4];
      set_float4(c, 0.8f, 0.8f, 0.8f, 1.0f);
      aiColor4D diffuse;
      if(AI_SUCCESS == aiGetMaterialColor(mtl, AI_MATKEY_COLOR_DIFFUSE, &diffuse))
	color4_to_float4(&diffuse, c);
      memcpy(aMat.diffuse, c, sizeof(c));

      set_float4(c, 0.2f, 0.2f, 0.2f, 1.0f);
      aiColor4D ambient;
      if(AI_SUCCESS == aiGetMaterialColor(mtl, AI_MATKEY_COLOR_AMBIENT, &ambient))
	color4_to_float4(&ambient, c);
      memcpy(aMat.ambient, c, sizeof(c));

      set_float4(c, 0.0f, 0.0f, 0.0f, 1.0f);
      aiColor4D specular;
      if(AI_SUCCESS == aiGetMaterialColor(mtl, AI_MATKEY_COLOR_SPECULAR, &specular))
	color4_to_float4(&specular, c);
      memcpy(aMat.specular, c, sizeof(c));

      set_float4(c, 0.0f, 0.0f, 0.0f, 1.0f);
      aiColor4D emission;
      if(AI_SUCCESS == aiGetMaterialColor(mtl, AI_MATKEY_COLOR_EMISSIVE, &emission))
	color4_to_float4(&emission, c);
      memcpy(aMat.emissive, c, sizeof(c));

      float shininess = 0.0;
      unsigned int max;
      aiGetMaterialFloatArray(mtl, AI_MATKEY_SHININESS, &shininess, &max);
      aMat.shininess = shininess;

      glGenBuffers(1,&(aMesh.uniformBlockIndex));
      glBindBuffer(GL_UNIFORM_BUFFER,aMesh.uniformBlockIndex);
      glBufferData(GL_UNIFORM_BUFFER, sizeof(aMat), (void *)(&aMat), GL_STATIC_DRAW);

      myMeshes.push_back(aMesh);
    }
}

// ------------------------------------------------------------
/// Reshape Callback Function
void changeSize(int w, int h) {

  float ratio;
  // Prevent a divide by zero, when window is too short
  // (you cant make a window of zero width).
  if(h == 0)
    h = 1;

  // Set the viewport to be the entire window
  glViewport(0, 0, w, h);

  ratio = (1.0f * w) / h;
  buildProjectionMatrix(gvar_proj_mtx_horiz_fov,\
			ratio,\
			gvar_proj_mtx_near_clip_plane,\
			gvar_proj_mtx_far_clip_plane);
}

// ------------------------------------------------------------
/// Render stuff

/// Render Assimp Model
void recursive_render (const aiScene *sc, const aiNode* nd)
{
  // Get node transformation matrix
  aiMatrix4x4 m = nd->mTransformation;
  // OpenGL matrices are column major
  m.Transpose();

  // save model matrix and apply node transformation
  pushMatrix();

  float aux[16];
  memcpy(aux,&m,sizeof(float) * 16);
  multMatrix(modelMatrix, aux);
  setModelMatrix();

  // draw all meshes assigned to this node
  for (unsigned int n=0; n < nd->mNumMeshes; ++n){
    // bind material uniform
    glBindBufferRange(GL_UNIFORM_BUFFER, materialUniLoc, myMeshes[nd->mMeshes[n]].uniformBlockIndex, 0, sizeof(struct MyMaterial));	
    // bind texture
    glBindTexture(GL_TEXTURE_2D, myMeshes[nd->mMeshes[n]].texIndex);
    // bind VAO
    glBindVertexArray(myMeshes[nd->mMeshes[n]].vao);
    // draw
    glDrawElements(GL_TRIANGLES,myMeshes[nd->mMeshes[n]].numFaces*3,GL_UNSIGNED_INT,0);

  }

  // draw all children
  for (unsigned int n=0; n < nd->mNumChildren; ++n){
    recursive_render(sc, nd->mChildren[n]);
  }
  popMatrix();
}

/// Rendering Callback Function
void renderScene(void) {

  int i,j,k;
  for(i=-1;i<gvar_num_rot_x;i++){ // @todo, why does this start at -1 but others start at 0?  affects exit condition of loop
    for(j=0;j<gvar_num_rot_y;j++){
      for(k=0;k<gvar_num_rot_z;k++){
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	// set camera matrix
	setCamera(camX,camY,camZ,0,0,0);

	// set the model matrix to the identity Matrix
	setIdentityMatrix(modelMatrix,4);
	
	// sets the model matrix to a scale matrix so that the model fits in the window; scaleFactor is determined by looking at the size of the object and trying to fit the object in the window
	scale(scaleFactor, scaleFactor, scaleFactor);
	
    	//rotate(90,0.f,0.f,1.f);
    	rotate(-90,1.f,0.f,0.f);
    	rotate(-90,0.f,0.f,1.f);
    
	rotate(gvar_delta_rot_x*i,1.f,0.f,0.f); // rotate it around the x axis	
	rotate(gvar_delta_rot_y*j,0.f,1.f,0.f); // rotate it around the y axis
	rotate(gvar_delta_rot_z*k,0.f,0.f,1.f); // rotate it around the z axis

	// use our shader
	glUseProgram(program);
	glUniform1i(texUnit,0);

	recursive_render(scene, scene->mRootNode);

	// swap buffers
	glutSwapBuffers();

	int w=gvar_render_size_width,h=gvar_render_size_height;	//save color image    
	char filename[50];
	/*IplImage* src=cvCreateImage(cvSize(w,h), IPL_DEPTH_8U,1);   //save depth image
	  glPixelStorei(GL_PACK_ALIGNMENT, 1);
	  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
	  glReadPixels(0, 0, w, h, GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, src->imageData);
	  cvFlip(src, src, 0);      //flip image in x axes	
	  sprintf(filename, "d_%02d_%02d.png",i,k);
	  cvSaveImage(filename,src,0);*/
	
	IplImage* img=cvCreateImage(cvSize(w,h), IPL_DEPTH_8U,3);
    	glPixelStorei(GL_PACK_ALIGNMENT, 1);
    	glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    	glReadPixels(0, 0, w, h, GL_BGR_EXT, GL_UNSIGNED_BYTE, img->imageData);
	cvFlip(img, img, 0);	
    	sprintf(filename, "./output/c_%02d_%02d_%02d.png",i+1,j,k);
	cvSaveImage(filename,img);
		
      }
    }

    //printf( "i %d j %d k %d\n", i, j, k );
    
    if ( i == gvar_num_rot_x-1 &&
	 j == gvar_num_rot_y &&
	 k == gvar_num_rot_z ) {
      printf( "Exiting loop\n" );
      throw 999; // Trick to exit glutMainLoop from https://www.opengl.org/discussion_boards/showthread.php/166643-how-to-come-out-from-glutMainLoop
      //exit(0);
    }

  }

}

// --------------------------------------------------------
/// Shader Stuff

///
void printShaderInfoLog(GLuint obj)
{
  int infologLength = 0;
  int charsWritten  = 0;
  char *infoLog;

  glGetShaderiv(obj, GL_INFO_LOG_LENGTH,&infologLength);

  if (infologLength > 0)
    {
      infoLog = (char *)malloc(infologLength);
      glGetShaderInfoLog(obj, infologLength, &charsWritten, infoLog);
      printf("%s\n",infoLog);
      free(infoLog);
    }
}

///
void printProgramInfoLog(GLuint obj)
{
  int infologLength = 0;
  int charsWritten  = 0;
  char *infoLog;

  glGetProgramiv(obj, GL_INFO_LOG_LENGTH,&infologLength);

  if (infologLength > 0)
    {
      infoLog = (char *)malloc(infologLength);
      glGetProgramInfoLog(obj, infologLength, &charsWritten, infoLog);
      printf("%s\n",infoLog);
      free(infoLog);
    }
}

///
GLuint setupShaders() {
  char *vs = NULL,*fs = NULL;
  GLuint p,v,f;

  v = glCreateShader(GL_VERTEX_SHADER);
  f = glCreateShader(GL_FRAGMENT_SHADER);

  vs = textFileRead( gvar_vertex_fname /*VERTEX_FILENAME*/ );
  fs = textFileRead( gvar_fragment_fname /*FRAGMENT_FILENAME*/ );

  const char * vv = vs;
  const char * ff = fs;

  glShaderSource(v, 1, &vv,NULL);
  glShaderSource(f, 1, &ff,NULL);

  free(vs);free(fs);

  glCompileShader(v);
  glCompileShader(f);

  printShaderInfoLog(v);
  printShaderInfoLog(f);

  p = glCreateProgram();
  glAttachShader(p,v);
  glAttachShader(p,f);

  glBindFragDataLocation(p, 0, "output");

  glBindAttribLocation(p,vertexLoc,"position");
  glBindAttribLocation(p,normalLoc,"normal");
  glBindAttribLocation(p,texCoordLoc,"texCoord");

  glLinkProgram(p);
  glValidateProgram(p);
  printProgramInfoLog(p);

  program = p;
  vertexShader = v;
  fragmentShader = f;
	
  GLuint k = glGetUniformBlockIndex(p,"Matrices");
  glUniformBlockBinding(p, k, matricesUniLoc);
  glUniformBlockBinding(p, glGetUniformBlockIndex(p,"Material"), materialUniLoc);

  texUnit = glGetUniformLocation(p,"texUnit");

  return(p);
}

// ------------------------------------------------------------
/// Model loading and OpenGL setup

///
int init()					 
{
  if (!Import3DFromFile( gvar_model_fname /*MODEL_FILENAME*/ )) 
    return(0);

  LoadGLTextures(scene);

  glGetUniformBlockIndex = (PFNGLGETUNIFORMBLOCKINDEXPROC) glutGetProcAddress("glGetUniformBlockIndex");
  glUniformBlockBinding = (PFNGLUNIFORMBLOCKBINDINGPROC) glutGetProcAddress("glUniformBlockBinding");
  glGenVertexArrays = (PFNGLGENVERTEXARRAYSPROC) glutGetProcAddress("glGenVertexArrays");
  glBindVertexArray = (PFNGLBINDVERTEXARRAYPROC)glutGetProcAddress("glBindVertexArray");
  glBindBufferRange = (PFNGLBINDBUFFERRANGEPROC) glutGetProcAddress("glBindBufferRange");
  glDeleteVertexArrays = (PFNGLDELETEVERTEXARRAYSPROC) glutGetProcAddress("glDeleteVertexArrays");

  program = setupShaders();
  genVAOsAndUniformBuffer(scene);

  glEnable(GL_DEPTH_TEST);		
  glClearColor(0.0f, 0.0f, 0.0f, 0.0f);

  glGenBuffers(1,&matricesUniBuffer);
  glBindBuffer(GL_UNIFORM_BUFFER, matricesUniBuffer);
  glBufferData(GL_UNIFORM_BUFFER, MatricesUniBufferSize,NULL,GL_DYNAMIC_DRAW);
  glBindBufferRange(GL_UNIFORM_BUFFER, matricesUniLoc, matricesUniBuffer, 0, MatricesUniBufferSize);	//setUniforms();
  glBindBuffer(GL_UNIFORM_BUFFER,0);

  glEnable(GL_MULTISAMPLE);
  return true;					
}

// ------------------------------------------------------------
/// Main function
int main(int argc, char **argv) {
  // set default param. values
  strcpy( gvar_vertex_fname, VERTEX_FILENAME );
  strcpy( gvar_fragment_fname, FRAGMENT_FILENAME );
  strcpy( gvar_model_fname, MODEL_FILENAME );

  gvar_delta_rot_x = DELTA_ROT_X;
  gvar_delta_rot_y = DELTA_ROT_Y;
  gvar_delta_rot_z = DELTA_ROT_Z;
  gvar_num_rot_x = NUM_ROT_X;
  gvar_num_rot_y = NUM_ROT_Y;
  gvar_num_rot_z = NUM_ROT_Z;

  gvar_proj_mtx_horiz_fov = PROJ_MTX_HORIZONTAL_FOV;
  gvar_proj_mtx_near_clip_plane = PROJ_MTX_NEAR_CLIP_PLANE;
  gvar_proj_mtx_far_clip_plane = PROJ_MTX_FAR_CLIP_PLANE;
  gvar_render_size_width = RENDER_SIZE_WIDTH;
  gvar_render_size_height = RENDER_SIZE_HEIGHT;

  // @todo take param's from cmd line or config file

  printf( "vertex, fragment, and model filenames: %s, %s, %s\n",\
	  gvar_vertex_fname, gvar_fragment_fname, gvar_model_fname );
  printf ( "Delta rotation x, y, z (deg.): %.2g, %.2g, %.2g\n",
	   gvar_delta_rot_x, gvar_delta_rot_y, gvar_delta_rot_z );
  printf( "Number of rotations: %d, %d, %d\n",\
	  gvar_num_rot_x, gvar_num_rot_y, gvar_num_rot_z );
  // @todo figure out what angle ranges are covered with these param's (need to know start/stop conditions of code)
  printf( "Projection matrix horizontal FOV, near clip plane, and far clip plane; render size width, render size height: %.2g, %.2g, %.2g, %d, %d\n",\
	  gvar_proj_mtx_horiz_fov, gvar_proj_mtx_near_clip_plane, gvar_proj_mtx_far_clip_plane, gvar_render_size_width, gvar_render_size_height);

  //printf ("--> Close graphics window to quit program <--\n\n" );

  try {

  glutInit(&argc, argv);

  glutInitDisplayMode(GLUT_DEPTH|GLUT_DOUBLE|GLUT_RGBA|GLUT_MULTISAMPLE);

  glutInitContextVersion (3, 3);
  glutInitContextFlags (GLUT_COMPATIBILITY_PROFILE );

  glutInitWindowPosition(100,100);
  glutInitWindowSize(gvar_render_size_width,gvar_render_size_height);
  glutCreateWindow("Model");
		
  //Callback Registration
  glutDisplayFunc(renderScene);
  glutReshapeFunc(changeSize);
  //glutIdleFunc(renderScene);

  //Init GLEW
  glewInit();
  if (!glewIsSupported("GL_VERSION_3_3")){
    printf("OpenGL 3.3 not supported\n");
    return(1);
  }

  //Init the app (load model and textures) and OpenGL
  if (!init())
    printf("Could not Load the Model\n");

  printf ("Vendor: %s\n", glGetString (GL_VENDOR));
  printf ("Renderer: %s\n", glGetString (GL_RENDERER));
  printf ("Version: %s\n", glGetString (GL_VERSION));
  printf ("GLSL: %s\n", glGetString (GL_SHADING_LANGUAGE_VERSION));

  //return from main loop
  glutSetOption(GLUT_ACTION_ON_WINDOW_CLOSE, GLUT_ACTION_GLUTMAINLOOP_RETURNS);
  glutMainLoop();

  }
  catch(int n) {
    if ( n == 999 )
      printf( "Finished; exiting\n" );
    else
      printf( "Unknown exception: %d", n );
  }
  catch(...) {
    printf( "Unknown exception" );
  }

  // cleaning up
  textureIdMap.clear();  

  // clear myMeshes stuff
  for (unsigned int i = 0; i < myMeshes.size(); ++i) {		
    glDeleteVertexArrays(1,&(myMeshes[i].vao));
    glDeleteTextures(1,&(myMeshes[i].texIndex));
    glDeleteBuffers(1,&(myMeshes[i].uniformBlockIndex));
  }
  // delete buffers
  glDeleteBuffers(1,&matricesUniBuffer);

  return(0);
}
