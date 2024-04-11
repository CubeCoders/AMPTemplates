#!/bin/bash
find ./arma3/233780/steamapps/workshop/content/107410/ -depth -name "*[A-Z]*" -print0 |\
 xargs -0 -I {} bash -c "mv \"{}\" \"\`echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,'\`\"";\
 cd ./arma3/233780 &&\
 find ./steamapps/workshop/content/107410 -maxdepth 1 -mindepth 1 -type d -exec ln -sf -t ./ {} +
exit 0