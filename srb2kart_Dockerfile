FROM debian:bookworm-20250407 AS build

# Running upgrade command.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y upgrade

# Apt-get install all required dependencies to compile this release.
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential libpng-dev zlib1g-dev libsdl2-dev libsdl2-mixer-dev libgme-dev libgme0 libopenmpt-dev libupnp-dev libupnp13 libcurl4-openssl-dev nasm git wget unzip cmake patch
# Go to root
WORKDIR /root/
RUN git clone -b "v1.6" https://github.com/STJr/Kart-Public
ENV LIBGME_CFLAGS=""
ENV LIBGME_LDFLAGS="-lgme"
# Need to get data.
RUN wget https://github.com/STJr/Kart-Public/releases/download/v1.6/AssetsLinuxOnly.zip -O /root/Data.zip
# Unzip and copy needed files.
RUN unzip Data.zip
RUN mkdir /root/Kart-Public/assets/installer
RUN unzip Data.zip -d /root/Kart-Public/assets/installer/
WORKDIR /root/Kart-Public/
# Need to apply a patch before we build. Download the patch.
RUN wget https://raw.githubusercontent.com/Hacksawfred3232/CustAMPTemplates/refs/heads/main/extrafiles/SRB2Kart_NoForkPatch.patch
# Apply.
RUN patch -p1 < SRB2Kart_NoForkPatch.patch
RUN mkdir build
WORKDIR /root/Kart-Public/build
# Compile files.
RUN cmake ../
RUN make -j 4
# Binary should be compiled now.
# There are still debug symbols on this file. Strip them.
RUN strip --strip-debug bin/srb2kart
# Copy the binary file.
RUN cp bin/srb2kart /root/srb2kart
# This is where the build ends here.

FROM cubecoders/ampbase:deb12
# Retarget the above to cubecoders/ampbase:deb12-srb2kart
# Copy from our builder the main file. updates.json will copy this to our working directory.
COPY --from=build /root/srb2kart /srb2kartlinux.exe
# Running upgrade command.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y upgrade
# Shortened version of the list above.
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install libpng-dev zlib1g-dev libsdl2-dev libsdl2-mixer-dev libgme-dev libgme0 libopenmpt-dev libupnp-dev libupnp13 libcurl4-openssl-dev wget unzip
# Running clean up.
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
# Ensure that WORKDIR is /
WORKDIR /
