#!/bin/bash
find ./arma2oa/33935/steamapps/workshop/content/33930/ -depth -name "*[A-Z]*" -print0 |\
 xargs -0 -I {} bash -c "mv \"{}\" \"\`echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,'\`\""
exit 0