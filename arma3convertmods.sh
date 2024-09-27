#!/bin/bash
[ -d ./arma3/233780/steamapps/workshop/content/107410 ] &&\
 find ./arma3/233780/steamapps/workshop/content/107410/ -depth -name "*[A-Z]*" -print0 |\
 xargs -0 -I {} bash -c "mv \"{}\" \"\`echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,'\`\"" >/dev/null 2>&1
exit 0