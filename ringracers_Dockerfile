FROM debian:bookworm-20250407 AS build

# Running upgrade command.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y upgrade

# Apt-get install all required dependencies to compile this release.
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential libcurl4-openssl-dev zlib1g-dev libpng++-dev libpng-dev libogg-dev libvorbis-dev libvpx-dev libyuv-dev libupnp-dev libupnp13 libsdl2-dev libsdl2-mixer-dev nasm git wget unzip cmake ninja-build
# Go to root
WORKDIR /root/
RUN git clone -b "v2.3" https://github.com/KartKrewDev/RingRacers
#ENV LIBGME_CFLAGS=""
#ENV LIBGME_LDFLAGS="-lgme"
# Need to get data.
RUN wget https://github.com/KartKrewDev/RingRacers/releases/download/v2.3/Dr.Robotnik.s-Ring-Racers-v2.3-Assets.zip -O /root/Data.zip
# Unzip and copy needed files.
RUN unzip Data.zip
RUN mkdir /root/RingRacers/assets/installer
RUN unzip Data.zip -d /root/RingRacers/assets/installer/
WORKDIR /root/RingRacers/
RUN mkdir build
WORKDIR /root/RingRacers/build
# Compile files.
RUN cmake -B ./ --preset ninja-release ../
RUN cmake --build ./
# Bin is in /root/RingRacers/build/bin
# There are still debug symbols on this file. Strip them.
RUN strip --strip-debug bin/ringracers_v2.3
# Copy the binary file.
RUN cp bin/ringracers_v2.3 /root/ringracers
# This is where the build ends here.

FROM cubecoders/ampbase:deb12
# Retarget the above to cubecoders/ampbase:deb12-ringracers
# Copy from our builder the main file. updates.json will copy this to our working directory.
COPY --from=build /root/ringracers /ringracerslinux.exe
# Running upgrade command.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y upgrade
# Shortened version of the list above.
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install libcurl4-openssl-dev zlib1g-dev libpng++-dev libpng-dev libogg-dev libvorbis-dev libvpx-dev libyuv-dev libupnp-dev libupnp13 libsdl2-dev libsdl2-mixer-dev wget unzip
# Running clean up.
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
# Ensure that WORKDIR is /
WORKDIR /
