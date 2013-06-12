#!/bin/bash

####################
### DGF 20080114 ###
####################

##############################
### Dichiarazione funzioni ###
##############################

declare -F ControlloParametriScript
declare -F Yesterday
declare -F GetLog
declare -F SendTrap
declare -F GetConfigurationFile
declare -F CaricaArray
declare -F GetYesterdayTimestampFile
declare -F SelectionFromArchitecture
declare -F ControlPathDownloadServerMaster
declare -F BuildFileList
declare -F ControlloSizeLog
declare -F CopyPastFile
declare -F LaunchCrypt
declare -F LaunchCryptFileList
declare -F LaunchCopySendFile
declare -F LaunchMarcaturaTemporale


############################
### DEFINIZIONE FUNZIONI ###
############################

### La funzione mi serve per calcolare il numero di secondi corrispondenti alla data che mi interessa ###
function ControlloParametriScript() {
        if [ $# -eq 0 ];then
                NUM_DAY_BEFORE=86400
        else
                NUM_DAY_BEFORE=$(expr $1 \* 86400)
        fi
}

function Yesterday() {
        YESTERDAY=$(perl -MPOSIX -le 'print strftime("%Y-%m-%d",localtime(time - $ARGV[0]))' $1)
        DAY_BEFORE=$(perl -MPOSIX -le 'print strftime("%Y%m%d",localtime(time - 86400))')
}

function GetLog() {
        DATA_LOG="$(date +%Y-%m-%d\ %H:%M:%S)"
        if [ "${SWITCH_MULTI}" == "ON" ];then
                echo "${DATA_LOG} - $1" >> ${PATH_LOG}/conservazione_marcatura_temporale_$(date +%Y%m%d).log
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

function SendTrap() {
        echo "optiserver*invio trap conservazione_log_marcati-X.X.sh*2*$1"|${NSCA_PATH} -H ${IP_ADD} -d "*" -c /usr/local/nagios/bin/send_nsca.cfg
}

function GetConfigurationFile() {
        egrep -v $"\#" ${PATH_CONF}/${FILE_SERVER_LIST} > ${PATH_WORK}/lista_file.tmp
}

function CaricaArray() {
        unset ARRAY
        IDX=0
        while read LINE
        do
                ARRAY[IDX]=${LINE}
                IDX=$(expr ${IDX} + 1)
        done < ${PATH_WORK}/lista_file.tmp
        if [ -e ${PATH_WORK}/lista_file.tmp ];then
                rm ${PATH_WORK}/lista_file.tmp
        fi
}

function GetYesterdayTimestampFile() {
        Yesterday ${NUM_DAY_BEFORE}
        GetConfigurationFile
        CaricaArray

        for  (( i=0; i<=$((${#ARRAY[@]} - 1)); i++ ))
        do
                HOSTNAME=$(echo ${ARRAY[i]}|${AWK} '{print $1}')
                IP_HOST=$(echo ${ARRAY[i]}|${AWK} '{print $2}')
                PATH_MARCATURATEMPORALE=$(echo ${ARRAY[i]}|${AWK} '{print $3}')
                PIATTAFORMA=$(echo ${ARRAY[i]}|${AWK} '{print $4}')
                TEST_PIATTAFORMA=$(echo ${PIATTAFORMA}|${AWK} -F"/" '{print NF}')
                FILE_TO_CRYPT=$(echo ${ARRAY[i]}|${AWK} '{print $5}')

                if [ ${TEST_PIATTAFORMA} -eq 1 ];then
                        FLAG=1
                        ControlPathDownloadServerMaster ${PIATTAFORMA} ${HOSTNAME}
                        SelectionFromArchitecture ${PIATTAFORMA} ${HOSTNAME} ${IP_HOST} ${PATH_MARCATURATEMPORALE} ${HOSTNAME} ${YESTERDAY}
                        BuildFileList ${PIATTAFORMA} ${HOSTNAME} ${YESTERDAY}
                        LaunchCrypt ${ACTION} ${PATH_DOWNLOAD_SERVERMASTER}/${PIATTAFORMA}/${HOSTNAME} ${YESTERDAY} ${FILE_TO_CRYPT} ${HOSTNAME}

                else
                        FLAG=2
                        PIATTAFORMA_1=$(echo ${PIATTAFORMA}|${AWK} -F"/" '{print $1}')
                        PIATTAFORMA_2=$(echo ${PIATTAFORMA}|${AWK} -F"/" '{print $2}')
                        ControlPathDownloadServerMaster ${PIATTAFORMA_1} ${HOSTNAME}
                        SelectionFromArchitecture ${PIATTAFORMA_1} ${HOSTNAME} ${IP_HOST} ${PATH_MARCATURATEMPORALE} ${LISIT} ${YESTERDAY}
                        BuildFileList ${PIATTAFORMA_1} ${HOSTNAME} ${YESTERDAY} ${DAY_BEFORE}
                        LaunchCrypt ${ACTION} ${PATH_DOWNLOAD_SERVERMASTER}/${PIATTAFORMA_1}/${HOSTNAME} ${YESTERDAY} ${FILE_TO_CRYPT} ${HOSTNAME}
                        ControlPathDownloadServerMaster ${PIATTAFORMA_2} ${HOSTNAME}
                        SelectionFromArchitecture ${PIATTAFORMA_2} ${HOSTNAME} ${IP_HOST} ${PATH_MARCATURATEMPORALE} ${LISIT} ${YESTERDAY}
                        BuildFileList ${PIATTAFORMA_2} ${HOSTNAME} ${YESTERDAY}
                        LaunchCrypt ${ACTION} ${PATH_DOWNLOAD_SERVERMASTER}/${PIATTAFORMA_2}/${HOSTNAME} ${YESTERDAY} ${FILE_TO_CRYPT} ${HOSTNAME}
                fi
        done
}

function SelectionFromArchitecture() {
        ### controllo il flag per determinare in quale piattaforma ci troviamo ###
        if [ ${FLAG} -ne 1 ];then
                ### controllo il flag per determinare in quale piattaforma ci troviamo ###
                if [ "$1" != "PEC_LISIT" ];then
                        su ${LOCAL_USER} -c "ssh ${USER_REMOTO}@$3 ls $4 |grep -iv $5| grep $6|${AWK} -v user_remoto=${USER_REMOTO} -v ip_host=$3 -v path_marctmp=$4 -v path_download=${PATH_DOWNLOAD_SERVERMASTER}/$1/$2/  '{print \"scp\",user_remoto\"@\"ip_host\":\"path_marctmp\"/\"\$1,path_download}'|bash"
                        if [ $? -eq 0 ];then
                                GetLog "[INFO] scp dal server $2 piattaforma $1 per la data $6 andato bene"
                        else
                                GetLog "[ERRORE] scp non avvenuta correttamente dal server $2 piattaforma $1 per la data $6 invio trap"
                                SendTrap "Error scp $2"
                        fi
                else
                        su ${LOCAL_USER} -c "ssh ${USER_REMOTO}@$3 ls $4 |grep -i $5| grep $6|${AWK} -v user_remoto=${USER_REMOTO} -v ip_host=$3 -v path_marctmp=$4 -v path_download=${PATH_DOWNLOAD_SERVERMASTER}/$1/$2/  '{print \"scp\",user_remoto\"@\"ip_host\":\"path_marctmp\"/\"\$1,path_download}'|bash"
                        if [ $? -eq 0 ];then
                                GetLog "[INFO] scp dal server $2 piattaforma $1 per la data $6 andato bene"
                        else
                                GetLog "[ERRORE] scp non avvenuta correttamente dal server $2 piattaforma $1 per data $6 invio trap"
                                SendTrap "Error scp $2"
                        fi
                fi
        else
                su ${LOCAL_USER} -c "ssh ${USER_REMOTO}@$3 ls $4 |grep -i $5| grep $6|${AWK} -v user_remoto=${USER_REMOTO} -v ip_host=$3 -v path_marctmp=$4 -v path_download=${PATH_DOWNLOAD_SERVERMASTER}/$1/$2/  '{print \"scp\",user_remoto\"@\"ip_host\":\"path_marctmp\"/\"\$1,path_download}'|bash"
                if [ $? -eq 0 ];then
                        GetLog "[INFO] scp dal server $2 piattaforma $1 per la data $6 andato a buon fine"
                else
                        GetLog "[ERRORE] scp non avvenuta correttamente dal server $2 piattaforma $1 per data $6 invio trap"
                        SendTrap "Error scp $2"
                fi
        fi
}

### Funzione per il controllo dir sul server master ###
function ControlPathDownloadServerMaster() {
        if [ ! -d ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2 ];then
                GetLog "[INFO] dir ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2 non presente provo a crearla"
                mkdir -p ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2
                if [ $? -ne 0 ];then
                        GetLog "[ERRORE] non riesco a creare la dir ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2 invio trap ed esco"
                        SendTrap "Errore mkdir failed"
                        exit 1
                else
                        chown -R ${LOCAL_USER}:${LOCAL_GROUP} ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2
                        GetLog "[INFO] dir ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2 creata correttamente permessi settati"
                fi
        else
                CONTROL_FS_OCCUPATION=$(${DF} -k ${PATH_DOWNLOAD_SERVERMASTER}|${AWK} '{print $5}'|grep \%|${AWK} -F"%" '{print $1}')
                if [ ${CONTROL_FS_OCCUPATION} -gt ${WATERMARK_FS} ];then
                        GetLog "[WARNING] il F.S. ha superato la soglia del ${WATERMARK_FS} invio trap"
                        SendTrap "occupazione F.S. "
                fi
        fi
}

function BuildFileList() {
        TO_DAY=$(date +%Y%m%d)
        ls ${PATH_DOWNLOAD_SERVERMASTER}/$1/$2/*$3* > ${PATH_WORK}/elaboro_file.elab
        ControlloSizeLog $1
        while read elab
        do
                HASH=$(${OPENSSL} dgst -sha1 ${elab}|${AWK} '{print $2}')
                if [ $? -eq 0 ];then
                        GetLog "[INFO] generato hash del file ${elab}"
                else
                        GetLog "[ERRORE] hash non generato invio trap"
                        SendTrap "hash non generato"
                fi
                ls -lrt ${elab}|${AWK} -v path_file_store="${elab}" -v hash=${HASH} -v data=${TO_DAY} '{print path_file_store,$5,hash,data}' >> ${PATH_FILE_LOG}/$1/${SUFFIX_FILE_LOG}_$1_${TO_DAY}.list
        done < ${PATH_WORK}/elaboro_file.elab

        if [ -e ${PATH_WORK}/elaboro_file.elab ];then
                rm ${PATH_WORK}/elaboro_file.elab
        fi
}

### Controllo che il file di log non superi limiti di pericolo ###
function ControlloSizeLog() {
        SIZE_LOG=$(ls -l ${PATH_FILE_LOG}/$1/${SUFFIX_FILE_LOG}_$1_${TO_DAY}.list|${AWK} '{print $5}')
        if [ ${SIZE_LOG} -ge ${MAX_SIZE_LOG} ];then
                GetLog "[ERRORE] superata la size massima per un file di log.... invio trap ed esco"
                SendTrap "limite MAX file"
                exit 1
        fi
}

### Funzione che mi permette di impostare il file di log precedente per scrivere quello nuovo ###
function CopyPastFile() {
        y=0
        Yesterday
        NUMERO_PIATTAFORME_CONF=$(grep PIATTAFORME: ${PATH_CONF}/${FILE_SERVER_LIST}|${AWK} '{print NF-2}')
        while [ ${y} -lt ${NUMERO_PIATTAFORME_CONF} ]
        do
                PLATFORM=$(echo ${y}|grep PIATTAFORME: ${PATH_CONF}/${FILE_SERVER_LIST}|${AWK} -v var=${y} '{print $(NF-var) }')
                if [ -s ${PATH_FILE_LOG}/${PLATFORM}/${SUFFIX_FILE_LOG}_${PLATFORM}_${DAY_BEFORE}.list ];then
                        LAST_FILE_MONTH_DATE=$(ls ${PATH_FILE_LOG}/${PLATFORM}/${SUFFIX_FILE_LOG}_${PLATFORM}_${DAY_BEFORE}.list|${AWK} '{print substr($0,length($0)-12,6)}')
                        TO_DAY_MONTH_DATE=$(echo ${TO_DAY}|${AWK} '{print substr($0,0,length($0)-2)}')
                        if [ ${LAST_FILE_MONTH_DATE} -ne ${TO_DAY_MONTH_DATE} ];then
                                touch ${PATH_FILE_LOG}/${PLATFORM}/${SUFFIX_FILE_LOG}_${PLATFORM}_${TO_DAY}.list
                                GetLog "[INFO] Inizio nuovo mese"
                        else
                                cat ${PATH_FILE_LOG}/${PLATFORM}/${SUFFIX_FILE_LOG}_${PLATFORM}_${DAY_BEFORE}.list > ${PATH_FILE_LOG}/${PLATFORM}/${SUFFIX_FILE_LOG}_${PLATFORM}_${TO_DAY}.list
                                if [ $? -eq 0 ];then
                                        GetLog "[INFO] importo il file di log della giornata di ieri per la piattaforma ${PLATFORM}"
                                else
                                        GetLog "[ERRORE] file di log per la piattaforma : ${PLATFORM} non importato correttamente invio trap"
                                        SendTrap "Import file log ERROR"
                                fi
                        fi
                else
                        GetLog "[ERRORE] file di log per la piattaforma : ${PLATFORM} della giornata di ieri non presente invio trap"
                        SendTrap "file log non presente"
                fi
                y=$(expr ${y} + 1)
        done
}

### funzione che lancia la crittazione dei file ###
function LaunchCrypt() {
        if [ "${SWITCH_MULTI}" == "ON" ];then
                /bin/bash ${PATH_SCRIPT_CRYPT} $1 $2 $3 $4
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

function LaunchCryptFileList() {
        Yesterday $3
        if [ "${SWITCH_MULTI}" == "ON" ];then
                /bin/bash ${PATH_SCRIPT_CRYPT} $1 $2 ${YESTERDAY}
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

### funzione che copia o spedisce i file sullo storage ###
function LaunchCopySendFile() {
        Yesterday $1
        if [ "${SWITCH_MULTI}" == "ON" ];then
                /bin/bash ${PATH_SCRIPT_COPY_SEND_FILE} ${YESTERDAY}
                if [ $? -ne 0 ];then
                        GetLog "[ERRORE] copia remota-locale andata male"
                fi
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

function LaunchMarcaturaTemporale() {
        if [ "${SWITCH_MULTI}" == "ON" ];then
                /bin/bash ${PATH_SCRIPT_MARCATURATEMPORALE}
                if [ $? -ne 0 ];then
                        GetLog "[ERRORE] Marcatura temporale andata male"
                fi
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

############
### MAIN ###
############

### Carico le variabili globali dal file di Configurazione apposito ###
source /xxx/XXXX/Conf/variabili_globali.conf

### dichiarazione array ###
declare -a ARRAY

### Il watermark del F.S. e' espresso in % ###
declare -i WATERMARK_FS="90"

### Valore massimo per size file di log ###
declare -i MAX_SIZE_LOG="500000000"

### stringa presente nei log che mi permette di differenziarli da pec_itt ###
declare -r LISIT="lisit"

#declare -i AWK="/usr/xpg4/bin/awk"

declare -i TO_DAY=$(date +%Y%m%d)

if [ "${STAND_ALONE_MODE}" == "MULTI_MODE" ];then
        SWITCH_MULTI="ON"
        GetLog "[INFO] switch multi attivo"
else
        SWITCH_MULTI="OFF"
fi

ControlloParametriScript $1
CopyPastFile
GetYesterdayTimestampFile
LaunchMarcaturaTemporale
LaunchCryptFileList crypt_list_file ${PATH_SPOOL_MARCATURA} ${NUM_DAY_BEFORE}
LaunchCopySendFile ${NUM_DAY_BEFORE}
