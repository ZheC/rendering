#!/bin/sh
# render tea bottle with same rot. param's as plate; this is probably good for all objects symmetric around the z axis

echo "################################################################################"
echo rendering
echo "################################################################################"
mkdir -p output/tea_bottle
\rm -rf output/tea_bottle/*
./render ./input/17_Pet_bottle_pet_tea.ply output/tea_bottle   10 15  1   3  6  1 # Rx 15 Ry 10 Rz 0

# testing which axis is which
#./render ./input/17_Pet_bottle_pet_tea.ply output/tea_bottle   90  1  1   2  1  1 # Rx 90
#./render ./input/17_Pet_bottle_pet_tea.ply output/tea_bottle    1 90  1   1  2  1 # Ry 90
#./render ./input/17_Pet_bottle_pet_tea.ply output/tea_bottle    1  1 90   1  1  2 # Rz 90

# copy renders for training
mkdir -p ../vncc_train/input/tea_bottle
\rm -rf ../vncc_train/input/tea_bottle/*
cp output/tea_bottle/template*.* ../vncc_train/input/tea_bottle

# copy renders for testing
mkdir -p ../realtime_vncc/models/tea_bottle
\rm -rf ../realtime_vncc/models/tea_bottle/*
cp output/tea_bottle/template*.* ../realtime_vncc/models/tea_bottle

# train
echo "################################################################################"
echo training
echo "################################################################################"
cd ../vncc_train
mkdir -p ../vncc_train/output/tea_bottle
\rm -rf ../output/tea_bottle/*
\rm -rf ../pre/tea_bottle.yaml
./train ./input/tea_bottle ./output/tea_bottle ./pre/tea_bottle.yaml

# copy yaml for testing
cp ./pre/tea_bottle.yaml ../realtime_vncc/pre
