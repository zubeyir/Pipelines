#!/bin/bash
set -e

########################################## PREPARE FUNCTIONS ########################################## 

source ${HCPPIPEDIR}/global/scripts/log.shlib # Logging related functions
source ${HCPPIPEDIR}/global/scripts/fsl_version.shlib # Function for getting FSL version

show_tool_versions()
{
	# Show HCP pipelines version
	log_Msg "Showing HCP Pipelines version"
	cat ${HCPPIPEDIR}/version.txt

	# Show wb_command version
	log_Msg "Showing Connectome Workbench (wb_command) version"
#	${CARET7DIR}/wb_command -version

	# Show fsl version
	log_Msg "Showing FSL version"
#	fsl_version_get fsl_ver
	fsl_ver="5.0.8"
	log_Msg "FSL version: ${fsl_ver}"
}



########################################## READ COMMAND-LINE ARGUMENTS ##################################
g_script_name=`basename ${0}`
log_SetToolName "${g_script_name}"
log_Msg "${g_script_name} arguments: $@"

Subject="$1"
ResultsFolder="$2"
DownSampleFolder="$3"
LevelOnefMRINames="$4"
LevelOnefsfNames="$5"
LevelTwofMRIName="$6"
LevelTwofsfName="$7"
LowResMesh="$8"
FinalSmoothingFWHM="$9"
TemporalFilter="${10}"
VolumeBasedProcessing="${11}"
RegName="${12}"
Parcellation="${13}"
AdditionalPreprocessing="${14}"

log_Msg "Subject: ${Subject}"
log_Msg "ResultsFolder: ${ResultsFolder}"
log_Msg "DownSampleFolder: ${DownSampleFolder}"
log_Msg "LevelOnefMRINames: ${LevelOnefMRINames}"
log_Msg "LevelOnefsfNames: ${LevelOnefsfNames}"
log_Msg "LevelTwofMRIName: ${LevelTwofMRIName}"
log_Msg "LevelTwofsfName: ${LevelTwofsfName}"
log_Msg "LowResMesh: ${LowResMesh}"
log_Msg "FinalSmoothingFWHM: ${FinalSmoothingFWHM}"
log_Msg "TemporalFilter: ${TemporalFilter}"
log_Msg "VolumeBasedProcessing: ${VolumeBasedProcessing}"
log_Msg "RegName: ${RegName}"
log_Msg "Parcellation: ${Parcellation}"
log_Msg "AdditionalPreprocessing: ${AdditionalPreprocessing}"

show_tool_versions

########################################## MAIN ##################################

# Change '@' delimited arguments to space-delimited lists
# for use in for loops
LevelOnefMRINames=`echo $LevelOnefMRINames | sed 's/@/ /g'`
LevelOnefsfNames=`echo $LevelOnefsfNames | sed 's/@/ /g'`

if [ ! "${Parcellation}" = "NONE" ] ; then
  ParcellationString="_${Parcellation}"
  Extension="ptseries.nii"
  ScalarExtension="pscalar.nii"
else
  ParcellationString=""
  Extension="dtseries.nii"
  ScalarExtension="dscalar.nii"
fi

log_Msg "ParcellationString: ${ParcellationString}"
log_Msg "Extension: ${Extension}"
log_Msg "ScalarExtension: ${ScalarExtension}"

if [ ! "${RegName}" = "NONE" ] ; then
  RegString="_${RegName}"
else
  RegString=""
fi

log_Msg "RegString: ${RegString}"

SmoothingString="_s${FinalSmoothingFWHM}"
log_Msg "SmoothingString: ${SmoothingString}"

TemporalFilterString="_hp""$TemporalFilter"
log_Msg "TemporalFilterString: ${TemporalFilterString}"

if [ "${AdditionalPreprocessing}" = "FIX" ] ; then
	AdditionalPreprocessingString="_hp2000_clean"
elif [ "${AdditionalPreprocessing}" = "NONE" ] || [ -z "${AdditionalPreprocessing}" ]; then
	AdditionalPreprocessingString=""
else
	echo "ERROR: Unrecognized AdditionalPreprocessing Option: ${AdditionalPreprocessing}"
	echo ""
	exit 1
fi
log_Msg "AdditionalPreprocessingString: ${AdditionalPreprocessingString}"

LevelOneFEATDirSTRING=""
i=1
for LevelOnefMRIName in $LevelOnefMRINames ; do 
  LevelOnefsfName=`echo $LevelOnefsfNames | cut -d " " -f $i`
  LevelOneFEATDirSTRING="${LevelOneFEATDirSTRING}${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level1${RegString}${ParcellationString}.feat "
  i=$(($i+1))
done
NumFirstLevelFolders=$(($i-1))

FirstFolder=`echo $LevelOneFEATDirSTRING | cut -d " " -f 1`
ContrastNames=`cat ${FirstFolder}/design.con | grep "ContrastName" | cut -f 2`
NumContrasts=`echo ${ContrastNames} | wc -w`
LevelTwoFEATDir="${ResultsFolder}/${LevelTwofMRIName}/${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2${RegString}${ParcellationString}.feat"
if [ -e ${LevelTwoFEATDir} ] ; then
  rm -r ${LevelTwoFEATDir}
  mkdir ${LevelTwoFEATDir}
else
  mkdir -p ${LevelTwoFEATDir}
fi

# GCB: Need way to specify different template.fsf names
# GCB: Also need to verify template.fsf is present, and copy it here if not
cat ${ResultsFolder}/${LevelTwofMRIName}/${LevelTwofsfName}_hp200_s4_level2.fsf | sed s/_hp200_s4/${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}${RegString}${ParcellationString}/g > ${LevelTwoFEATDir}/design.fsf

#Make design files
log_Msg "Make design files"
DIR=`pwd`
cd ${LevelTwoFEATDir}
feat_model ${LevelTwoFEATDir}/design
cd $DIR

#Loop over Grayordinates and Standard Volume (if requested) Level 2 Analyses
log_Msg "Loop over Grayordinates and Standard Volume (if requested) Level 2 Analyses"
if [ ${VolumeBasedProcessing} = "YES" ] ; then
  Analyses="GrayordinatesStats StandardVolumeStats"
elif [ -z ${ParcellationString} ] ; then
  Analyses="GrayordinatesStats"
else
  Analyses="ParcellatedStats"
fi
log_Msg "Analyses: ${Analyses}"

for Analysis in ${Analyses} ; do
  log_Msg "Analysis: ${Analysis}"
  mkdir -p ${LevelTwoFEATDir}/${Analysis}
  
  #Copy over level one folders and convert CIFTI to NIFTI if required
  log_Msg "Copy over level one folders and convert CIFTI to NIFTI if required"
  # GCB: Need smarter check of available cope files to handle empty EVs
  # Simultaneously check what current $Analysis is, and whether there are stats files
  if [ -e ${FirstFolder}/${Analysis}/cope1.nii.gz ] ; then
    Grayordinates="NO"
    i=1
    for LevelOneFEATDir in ${LevelOneFEATDirSTRING} ; do
      mkdir -p ${LevelTwoFEATDir}/${Analysis}/${i}
      cp ${LevelOneFEATDir}/${Analysis}/* ${LevelTwoFEATDir}/${Analysis}/${i}
      i=$(($i+1))
    done
  elif [ -e ${FirstFolder}/${Analysis}/cope1.${Extension} ] ; then
    Grayordinates="YES"
    i=1
    for LevelOneFEATDir in ${LevelOneFEATDirSTRING} ; do
      mkdir -p ${LevelTwoFEATDir}/${Analysis}/${i}
      cp ${LevelOneFEATDir}/${Analysis}/* ${LevelTwoFEATDir}/${Analysis}/${i}
      cd ${LevelTwoFEATDir}/${Analysis}/${i}
      Files=`ls | grep .${Extension} | cut -d "." -f 1`
      cd $DIR
      for File in $Files ; do
        ${CARET7DIR}/wb_command -cifti-convert -to-nifti ${LevelTwoFEATDir}/${Analysis}/${i}/${File}.${Extension} ${LevelTwoFEATDir}/${Analysis}/${i}/${File}.nii.gz
        rm ${LevelTwoFEATDir}/${Analysis}/${i}/${File}.${Extension}
      done
      i=$(($i+1))
    done
  else
    echo "Level One Folder Not Found"
    # GCB: if expected Level 1 copes were not found, die!
    log_Msg "ERROR: Missing cope files in ${FirstFolder}/${Analysis}"
    exit 1
  fi
  
  #Create dof and Mask
  log_Msg "Create dof and Mask"
  MERGESTRING=""
  i=1
  while [ $i -le ${NumFirstLevelFolders} ] ; do
    dof=`cat ${LevelTwoFEATDir}/${Analysis}/${i}/dof`
    fslmaths ${LevelTwoFEATDir}/${Analysis}/${i}/res4d.nii.gz -Tstd -bin -mul $dof ${LevelTwoFEATDir}/${Analysis}/${i}/dofmask.nii.gz
    MERGESTRING=`echo "${MERGESTRING}${LevelTwoFEATDir}/${Analysis}/${i}/dofmask.nii.gz "`
    i=$(($i+1))
  done
  fslmerge -t ${LevelTwoFEATDir}/${Analysis}/dof.nii.gz $MERGESTRING
  fslmaths ${LevelTwoFEATDir}/${Analysis}/dof.nii.gz -Tmin -bin ${LevelTwoFEATDir}/${Analysis}/mask.nii.gz
  
  #Merge COPES and VARCOPES and run 2nd level analysis
  log_Msg "Merge COPES and VARCOPES and run 2nd level analysis"
  log_Msg "NumContrasts: ${NumContrasts}"
  i=1
  while [ $i -le ${NumContrasts} ] ; do
	log_Msg "i: ${i}"
    COPEMERGE=""
    VARCOPEMERGE=""
    j=1
    while [ $j -le ${NumFirstLevelFolders} ] ; do
      COPEMERGE="${COPEMERGE}${LevelTwoFEATDir}/${Analysis}/${j}/cope${i}.nii.gz "
      VARCOPEMERGE="${VARCOPEMERGE}${LevelTwoFEATDir}/${Analysis}/${j}/varcope${i}.nii.gz "
      j=$(($j+1))
    done
    fslmerge -t ${LevelTwoFEATDir}/${Analysis}/cope${i}.nii.gz $COPEMERGE
    fslmerge -t ${LevelTwoFEATDir}/${Analysis}/varcope${i}.nii.gz $VARCOPEMERGE
    flameo --cope=${LevelTwoFEATDir}/${Analysis}/cope${i}.nii.gz --vc=${LevelTwoFEATDir}/${Analysis}/varcope${i}.nii.gz --dvc=${LevelTwoFEATDir}/${Analysis}/dof.nii.gz --mask=${LevelTwoFEATDir}/${Analysis}/mask.nii.gz --ld=${LevelTwoFEATDir}/${Analysis}/cope${i}.feat --dm=${LevelTwoFEATDir}/design.mat --cs=${LevelTwoFEATDir}/design.grp --tc=${LevelTwoFEATDir}/design.con --runmode=fe
    i=$(($i+1))
  done

  #Cleanup Temporary Files
  log_Msg "Cleanup Temporary Files"
  j=1
  while [ $j -le ${NumFirstLevelFolders} ] ; do
    rm -r ${LevelTwoFEATDir}/${Analysis}/${j}
    j=$(($j+1))
  done

  #Convert Grayordinates NIFTI Files to CIFTI if necessary
  log_Msg "Convert Grayordinates NIFTI Files to CIFTI if necessary"
  if [ $Grayordinates = "YES" ] ; then
    cd ${LevelTwoFEATDir}/${Analysis}
    Files=`ls | grep .nii.gz | cut -d "." -f 1`
    cd $DIR
    for File in $Files ; do
      ${CARET7DIR}/wb_command -cifti-convert -from-nifti ${LevelTwoFEATDir}/${Analysis}/${File}.nii.gz ${LevelOneFEATDir}/${Analysis}/pe1.${Extension} ${LevelTwoFEATDir}/${Analysis}/${File}.${Extension} -reset-timepoints 1 1 
      rm ${LevelTwoFEATDir}/${Analysis}/${File}.nii.gz
    done
    i=1
    while [ $i -le ${NumContrasts} ] ; do
      cd ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat
      Files=`ls | grep .nii.gz | cut -d "." -f 1`
      cd $DIR
      for File in $Files ; do
        ${CARET7DIR}/wb_command -cifti-convert -from-nifti ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat/${File}.nii.gz ${LevelOneFEATDir}/${Analysis}/pe1.${Extension} ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat/${File}.${Extension} -reset-timepoints 1 1 
        rm ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat/${File}.nii.gz
      done
      i=$(($i+1))
    done        
  fi
  
  #Generate Files for Viewing
  log_Msg "Generate Files for Viewing Analysis = ${Analysis}"
  #GrayordinatesStats StandardVolumeStats ParcellatedStats
  if [[ "$Analysis" == "GrayordinatesStats" || "$Analysis" == "ParcellatedStats" ]] ; then
    # Initialize "merge strings" used to create wb_command -cifti-merge arguments
    zstatMergeSTRING=""
    copeMergeSTRING=""
	if [ -e ${LevelTwoFEATDir}/Contrasts.txt ] ; then
      rm ${LevelTwoFEATDir}/Contrasts.txt
	fi

	i=1
	while [ $i -le ${NumContrasts} ] ; do
      Contrast=`echo $ContrastNames | cut -d " " -f $i`
      zstat_name="${Subject}_${Contrast}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2_zstat${RegString}${ParcellationString}"
      cope_name="${Subject}_${Contrast}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2_cope${RegString}${ParcellationString}"
      echo "$zstat_name" >> ${LevelTwoFEATDir}/Contrasttemp.txt
      echo ${Contrast} >> ${LevelTwoFEATDir}/Contrasts.txt
      ${CARET7DIR}/wb_command -cifti-convert-to-scalar ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat/zstat1.${Extension} ROW ${LevelTwoFEATDir}/${zstat_name}.${ScalarExtension} -name-file ${LevelTwoFEATDir}/Contrasttemp.txt
      ${CARET7DIR}/wb_command -cifti-convert-to-scalar ${LevelTwoFEATDir}/${Analysis}/cope${i}.feat/cope1.${Extension} ROW ${LevelTwoFEATDir}/${cope_name}.${ScalarExtension} -name-file ${LevelTwoFEATDir}/Contrasttemp.txt
      zstatMergeSTRING=`echo "${zstatMergeSTRING}-cifti ${LevelTwoFEATDir}/${zstat_name}.${ScalarExtension} "`
      copeMergeSTRING=`echo "${copeMergeSTRING}-cifti ${LevelTwoFEATDir}/${cope_name}.${ScalarExtension} "`

      rm ${LevelTwoFEATDir}/Contrasttemp.txt
      i=$(($i+1))
	done

	merged_zstat_name="${Subject}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2_zstat${RegString}${ParcellationString}"
	merged_cope_name="${Subject}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2_cope${RegString}${ParcellationString}"
	${CARET7DIR}/wb_command -cifti-merge ${LevelTwoFEATDir}/${merged_zstat_name}.${ScalarExtension} ${zstatMergeSTRING}
	${CARET7DIR}/wb_command -cifti-merge ${LevelTwoFEATDir}/${merged_cope_name}.${ScalarExtension} ${copeMergeSTRING}

  elif [[ $Analysis == "StandardVolumeStats" ]] ; then
	log_Msg "Skipping Viewing Files for Analysis = $Analysis"
#    # Initialize "merge strings" used to create wb_command -cifti-merge arguments
#    volume_zstatMergeSTRING=""
#    volume_copeMergeSTRING=""
	if [ -e ${LevelTwoFEATDir}/Contrasts.txt ] ; then
      rm ${LevelTwoFEATDir}/Contrasts.txt
	fi

	i=1
	while [ $i -le ${NumContrasts} ] ; do
      Contrast=`echo $ContrastNames | cut -d " " -f $i`
      echo ${Contrast} >> ${LevelTwoFEATDir}/Contrasts.txt
#      volume_zstat_name="${Subject}_${Contrast}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2vol_zstat${RegString}${ParcellationString}"
#      volume_cope_name="${Subject}_${Contrast}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2vol_cope${RegString}${ParcellationString}"
#      echo "$volume_zstat_name" >> ${LevelTwoFEATDir}/Contrasttemp.txt
#      echo "OTHER" >> ${LevelTwoFEATDir}/wbtemp.txt
#      echo "1 255 255 255 255" >> ${LevelTwoFEATDir}/wbtemp.txt
#      ${CARET7DIR}/wb_command -volume-label-import ${LevelTwoFEATDir}/${Analysis}/mask.nii.gz ${LevelTwoFEATDir}/wbtemp.txt ${LevelTwoFEATDir}/StandardVolumeStats/mask.nii.gz -discard-others -unlabeled-value 0
#      rm ${LevelTwoFEATDir}/wbtemp.txt
#      ${CARET7DIR}/wb_command -cifti-create-dense-timeseries ${LevelTwoFEATDir}/${volume_zstat_name}.dtseries.nii -volume ${LevelTwoFEATDir}/StandardVolumeStats/cope${i}.feat/zstat1.nii.gz ${LevelTwoFEATDir}/StandardVolumeStats/mask.nii.gz -timestep 1 -timestart 1
#      ${CARET7DIR}/wb_command -cifti-create-dense-timeseries ${LevelTwoFEATDir}/${volume_cope_name}.dtseries.nii -volume ${LevelTwoFEATDir}/StandardVolumeStats/cope${i}.feat/cope1.nii.gz ${LevelTwoFEATDir}/StandardVolumeStats/mask.nii.gz -timestep 1 -timestart 1
#      ${CARET7DIR}/wb_command -cifti-convert-to-scalar ${LevelTwoFEATDir}/${volume_zstat_name}.dtseries.nii ROW ${LevelTwoFEATDir}/${volume_zstat_name}.dscalar.nii -name-file ${LevelTwoFEATDir}/Contrasttemp.txt
#      ${CARET7DIR}/wb_command -cifti-convert-to-scalar ${LevelTwoFEATDir}/${volume_cope_name}.dtseries.nii ROW ${LevelTwoFEATDir}/${volume_cope_name}.dscalar.nii -name-file ${LevelTwoFEATDir}/Contrasttemp.txt
#      rm ${LevelTwoFEATDir}/${volume_zstat_name}.dtseries.nii ${LevelTwoFEATDir}/${volume_cope_name}.dtseries.nii
#      volume_zstatMergeSTRING=`echo "${volume_zstatMergeSTRING}-cifti ${LevelTwoFEATDir}/${volume_zstat_name}.dscalar.nii "`
#      volume_copeMergeSTRING=`echo "${volume_copeMergeSTRING}-cifti ${LevelTwoFEATDir}/${volume_cope_name}.dscalar.nii "`
#      rm ${LevelTwoFEATDir}/Contrasttemp.txt
      i=$(($i+1))
	done

#	merged_volume_zstat_name="${Subject}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2vol_zstat${RegString}${ParcellationString}"
#	merged_volume_cope_name="${Subject}_${LevelTwofsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level2vol_cope${RegString}${ParcellationString}"
#	${CARET7DIR}/wb_command -cifti-merge ${LevelTwoFEATDir}/${merged_volume_zstat_name}.dscalar.nii ${volume_zstatMergeSTRING}  
#	${CARET7DIR}/wb_command -cifti-merge ${LevelTwoFEATDir}/${merged_volume_cope_name}.dscalar.nii ${volume_copeMergeSTRING}  
  else # $Analysis doesn't exist
	# $Analysis doesn't exist!
	log_Msg "ERROR: $Analysis doesn't exist when Generate Files for Viewing Analysis"
	exit 1
  fi

done  



