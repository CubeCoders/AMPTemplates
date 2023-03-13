#!/bin/bash
find ./dayz/1042420/steamapps/workshop/content/221100/ -type f -name "*[A-Z]*" -print0 |\
 xargs -0 -I {} bash -c "mv \"{}\" \"\`echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,'\`\"";\
 cd ./dayz/1042420 &&\
 find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d -exec ln -sf -t ./ {} +
exit 0