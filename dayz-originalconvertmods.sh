#!/bin/bash
find ./dayz/223350/steamapps/workshop/content/221100/ -depth -name "*[A-Z]*" -print0 |\
 xargs -0 -I {} bash -c "mv \"{}\" \"\`echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,'\`\"" >/dev/null 2>&1
exit 0