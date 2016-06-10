#!/bin/sh
# to run: sh ./tea_bottle.sh
# render tea bottle with same rot. param's as plate; this is probably good for all objects symmetric around the z axis

OBJ=tea_bottle
CAD_FILENAME=17_Pet_bottle_pet_tea.obj


echo "################################################################################"
echo rendering
echo "################################################################################"
mkdir -p output/$OBJ
\rm -rf output/$OBJ/*
./render ./input/$CAD_FILENAME output/$OBJ   10 15  1   3  6  1 # Rx 15 Ry 10 Rz 0

# testing which axis is which
#./render ./input/$CAD_FILENAME output/$OBJ   90  1  1   2  1  1 # Rx 90
#./render ./input/$CAD_FILENAME output/$OBJ    1 90  1   1  2  1 # Ry 90
#./render ./input/$CAD_FILENAME output/$OBJ    1  1 90   1  1  2 # Rz 90

# copy renders for training
mkdir -p ../vncc_train/input/$OBJ
\rm -rf ../vncc_train/input/$OBJ/*
cp output/$OBJ/template*.* ../vncc_train/input/$OBJ

# copy renders for testing
mkdir -p ../realtime_vncc/models/$OBJ
\rm -rf ../realtime_vncc/models/$OBJ/*
cp output/$OBJ/template*.* ../realtime_vncc/models/$OBJ

# train
echo "################################################################################"
echo training
echo "################################################################################"
cd ../vncc_train
mkdir -p ../vncc_train/output/$OBJ
\rm -rf ../output/$OBJ/*
\rm -rf ../pre/$OBJ.yaml
./train ./input/$OBJ ./output/$OBJ ./pre/$OBJ.yaml

# copy yaml for testing
cp ./pre/$OBJ.yaml ../realtime_vncc/pre
