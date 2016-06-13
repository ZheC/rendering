#!/bin/sh
# to run: sh ./tea_bottle.sh
# render tea bottle with same rot. param's as plate; this is probably good for all objects symmetric around the z axis

OBJ=tea_bottle
CAD_FILENAME=17_Pet_bottle_pet_tea.obj

# @todo, make sure ./render exists, ../vncc_train exists, etc.

echo "################################################################################"
echo "rendering $CAD_FILENAME to output/$OBJ"
echo "  renders will be copied to ../vncc_train/input/$OBJ (for training)"
echo "  renders will be copied to ../realtime_vncc/models/$OBJ (for testing)"
echo "################################################################################"
# rendering
mkdir -p output/$OBJ
\rm -rf output/$OBJ/*
./render ./input/$CAD_FILENAME output/$OBJ   10 15  1   3  6  1 # Rx 15 Ry 10 Rz 0

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
echo "training ../vncc_train/input/$OBJ renders will be trained to ../vncc_train/output/$OBJ and made into ../vncc_train/pre/$OBJ.yaml"
echo "  YAML file will be copied to ../realtime_vncc/pre"
echo "################################################################################"
cd ../vncc_train
mkdir -p ../vncc_train/output/$OBJ
\rm -rf ../output/$OBJ/*
\rm -rf ../pre/$OBJ.yaml
./train ./input/$OBJ ./output/$OBJ ./pre/$OBJ.yaml

# copy yaml for testing
cp ./pre/$OBJ.yaml ../realtime_vncc/pre
