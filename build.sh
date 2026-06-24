#/bin/bash
script_dir="$( dirname -- "${BASH_SOURCE[0]}"; )"
outf=${1:-"PyWhlConfig.cmake"}
cp ${script_dir}/src/PyWhlConfig.cmake ${outf}
echo "set(PYWHL_CONTENTS_PYWHL_PY [====[" >> ${outf}
cat ${script_dir}/src/pywhl.py >> ${outf}
echo "]====])" >> ${outf}
echo "set(PYWHL_CONTENTS_EDITABLE_FINDER_PY [====[" >> ${outf}
cat ${script_dir}/src/editable_finder.py >> ${outf}
echo "]====])" >> ${outf}
echo "PyWhl_Init()" >> ${outf}
