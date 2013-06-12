#!/bin/bash

######################
### DGF 10/04/2008 ###
######################

##############################
### dichiarazioni funzioni ###
##############################
declare -F GetLog
declare -F SendTrap
declare -F Crypt
declare -F CryptListFile
declare -F Decrypt
declare -F GetConfigurationFile
declare -F CertificateVerify

############################
### DEFINIZIONE FUNZIONI ###
############################

function Yesterday() {
        YESTERDAY=$(perl -MPOSIX -le 'print strftime("%Y-%m-%d",localtime(time - $ARGV[0]))' $1)
        DAY_BEFORE=$(perl -MPOSIX -le 'print strftime("%Y%m%d",localtime(time - 86400))')
}

function GetLog() {
        DATA_LOG="$(date +%Y-%m-%d\ %H:%M:%S)"
        if [ "${SWITCH_MULTI}" == "ON" ];then
                echo "${DATA_LOG} - $1" >> ${PATH_LOG}/conservazione_crypt-$(date +%Y%m%d).log
        else
                echo "[INFO] script lanciato in modalita' stand alone"
        fi
}

function SendTrap() {
        ${SNMPTRAP} -v 2c -c resi -d -m ${MIB} ${IP_ADD} "" openTrap alarmId.0 i ${TRAPINDEX} alarmValue.0 s "$1";
}

function Crypt() {
        ### Controllo se il parametro esterno gli vienen passato ###
        if [ "$4" == "" ]||[ "$4" == "TUTTI" ];then
                CRYPT_FILE="*"
        else
                CRYPT_FILE=$4
        fi
        ### parte relativa ai dati presi dai server host ###
        /usr/xpg6/bin/ls $1/${CRYPT_FILE}*$3* > ${PATH_WORK}/lista_file_crypt.crp
        if [ $? -ne 0 ];then
                if [ "$5" == "${CLUSTER_ORA_PEC}" ];then
                        GetLog "[INFO] Claster su altro nodo"
                        exit 0
                else
                        GetLog "[ERRORE] File da crittografare ${CRYPT_FILE} non presente esco"
                        exit 1
                fi
        fi
        while read i
        do
                if [ ! -e $i-${CERTIFICATE_CHANGE_VALUES}.${SUFFIX_FOR_FILE_TO_CRYPT} ];then
###                     ${OPENSSL} smime -encrypt -aes256 -in $i -out $i-${CERTIFICATE_CHANGE_VALUES}.${SUFFIX_FOR_FILE_TO_CRYPT} -binary $2
                        ${OPENSSL} smime -encrypt -aes256 -in $i -out $i-${CERTIFICATE_CHANGE_VALUES}.${SUFFIX_FOR_FILE_TO_CRYPT} -binary $2
                        if [ $? -eq 0 ];then
                                GetLog "[INFO] encryption del file $i andata a buon fine"
                        else
                                GetLog "[ERRORE] encryption del file $i andata male invio trap"
                                SendTrap "Error encryption"
                        fi
                else
                        GetLog "[WARNING] file gia' presente"
                fi
        done < ${PATH_WORK}/lista_file_crypt.crp
        if [ -e ${PATH_WORK}/lista_file_crypt.crp ];then
                rm ${PATH_WORK}/lista_file_crypt.crp
        fi
}

function CryptListFile() {
        if [ "$3" == "" ];then
                NUM_DAY_BEFORE=86400
        else
                TEST_FIELD_DATE=$(echo $3|awk -F"-" '{print NF}')
                TEST_YEAR=$(echo $3|awk -F"-" '{print length($1)}')
                TEST_MONTH=$(echo $3|awk -F"-" '{print length($2)}')
                TEST_DAY=$(echo $3|awk -F"-" '{print length($3)}')
                if [ ${TEST_FIELD_DATE} -eq 3 ] && [ ${TEST_YEAR} -eq 4 ] && [ ${TEST_MONTH} -eq 2 ] &&  [ ${TEST_DAY} -eq 2 ];then
                        NUM_DAY_BEFORE=86400
                else
                        NUM_DAY_BEFORE=$(expr $3 \* 86400)
                fi
        fi

        Yesterday ${NUM_DAY_BEFORE}

        #ls $1/*$3*${YESTERDAY}*.tar.gz > ${PATH_WORK}/lista_file_list_to_crypt.crp
        ls $1/*${YESTERDAY}*.tar.gz > ${PATH_WORK}/lista_file_list_to_crypt.crp
        if [ $? -ne 0 ];then
                GetLog "[ERRORE] File da crittografare ${CRYPT_FILE} non presente "
                #####exit 1
        fi
        while read dd
        do
                ${OPENSSL} smime -encrypt -aes256 -in $dd -out $dd-${CERTIFICATE_CHANGE_VALUES}.${SUFFIX_FOR_FILE_TO_CRYPT} -binary $2
                if [ $? -eq 0 ];then
                        GetLog "[INFO] encryption del file $dd andata a buon fine"
                else
                        GetLog "[ERRORE] encryption del file $dd andata male invio trap"
                        SendTrap "Error encryption"
                fi
        done < ${PATH_WORK}/lista_file_list_to_crypt.crp
        if [ -e ${PATH_WORK}/lista_file_list_to_crypt.crp ];then
                rm ${PATH_WORK}/lista_file_list_to_crypt.crp
        fi
}

function Decrypt() {
        ls $1/*$3*-${CERTIFICATE_CHANGE_VALUES}*.${SUFFIX_FOR_FILE_TO_CRYPT} > ${PATH_WORK}/lista_file_decrypt.dcryt
        while read j
        do
                ${OPENSSL} smime  -decrypt -in $j  -out $j.${SUFFIX_FOR_FILE_TO_DECRYPT} -inkey $2
                if [ $? -eq 0 ];then
                        GetLog "[INFO] decryption del file $j andata a buon fine"
                else
                        GetLog "[ERRORE] encryption del file $j andata male invio trap"
                        SendTrap "Error decryption"
                fi
        done < ${PATH_WORK}/lista_file_decrypt.dcryt
        if [ -e ${PATH_WORK}/lista_file_decrypt.dcryt ];then
                rm ${PATH_WORK}/lista_file_decrypt.dcryt
        fi
}

function GetConfigurationFile() {
        egrep -v $"\#" ${PATH_CONF}/${FILE_SERVER_LIST} > ${PATH_WORK}/lista_file_crypt.tmp
}

### funzione che si occupa di verificare se il certificato pubblico e' cambiato ###
function CertificateVerify() {
        if [ -f ${PUBLICKEY_VERIFY_FILE} ];then
                TEST_CERT_VERIFY_OLD=$(cat ${PUBLICKEY_VERIFY_FILE}|grep -v cambio|tail -1|${AWK} '{print $1}')
                TEST_CERT_VERIFY=$(${OPENSSL} dgst -sha1 ${PUBLICKEY}|${AWK} '{print $2}')
                if [ "${TEST_CERT_VERIFY}" == "${TEST_CERT_VERIFY_OLD}" ];then
                        GetLog "[INFO] Certificato non cambiato"
                        CERTIFICATE_CHANGE_VALUES=$(cat ${PUBLICKEY_VERIFY_FILE}|grep ${TEST_CERT_VERIFY}|${AWK} '{print $2}')
                else
                        ### utilizzo la funzione random con 4 numeri ###
                        CERTIFICATE_CHANGE_VALUES=$(${OPENSSL} x509 -in ${PUBLICKEY} -serial -noout|${AWK} -F"=" '{print $2}')
                        echo $CERTIFICATE_CHANGE_VALUES
                        echo "cambio certificato avvenuto il $(date +%Y"-"%m"-"%d" "%H":"%M":"%S)" >> ${PUBLICKEY_VERIFY_FILE}
                        echo "${TEST_CERT_VERIFY}  ${CERTIFICATE_CHANGE_VALUES}" >> ${PUBLICKEY_VERIFY_FILE}
                        if [ $? -ne 0 ];then
                                GetLog "[ERRORE] generazione hash chiave pubblica non avvenuta correttamente invio trap esco"
                                SendTrap "errore hash"
                                exit 1
                        else
                                chmod 700 ${PUBLICKEY_VERIFY_FILE}
                                GetLog "[INFO] hash della chiave pubblica aggiornato"
                        fi
                fi
        else
                ### utilizzo stessa funzione per gestire la creazione per la prima volta del file ${PUBLICKEY_VERIFY_FILE} ###
                CERTIFICATE_CHANGE_VALUES=$(${OPENSSL} x509 -in ${PUBLICKEY} -serial -noout|${AWK} -F"=" '{print $2}')
                TEST_CERT_VERIFY=$(${OPENSSL} dgst -sha1 ${PUBLICKEY}|${AWK} '{print $2}')
                echo "${TEST_CERT_VERIFY} ${CERTIFICATE_CHANGE_VALUES}" > ${PUBLICKEY_VERIFY_FILE}
                if [ $? -ne 0 ];then
                        GetLog "[ERRORE] generazione hash della chiave pubblica non avvenuta invio trap"
                        SendTrap "errore hash"
                fi
        fi
}

############
### MAIN ###
############

### Lo script serve per crittografare dei file partendo da una repository ed una data, inoltre si puo' scegliere se  ###
### crittografare o decrittografare il file interessato. Lo script viene lanciato in automatico partendo dallo       ###
### script conservazione_log_marcati-X.X.sh ma puo' essere lanciato singolarmente passandogli i valori sopraindicati.###


### Carico le variabili globali dal file di Configurazione apposito ###
source /opt/CONSERVAZIONE_LOG_MARCATI/Conf/variabili_globali.conf

### Le variabili che prendo dallo script padre sono $1 il tipo di azione (crypt/decrypt), $2 il path della dir      ###
### di dove si trovano i file per cui deve fare il crypt/decript e $3 la data di ieri, $4 il nome iniviale del file ###
### da crittografare                                                                                                ###

### trasformo la stringa in tutti i caratteri minuscoli per il case ###
declare -r TRANSLATE=$(echo $1|tr [A-Z] [a-z])

### verifico lo switch se e' attivo ###
if [ "${STAND_ALONE_MODE}" == "MULTI_MODE" ];then
        SWITCH_MULTI="ON"
        GetLog "[INFO] switch multi attivo"
else
        SWITCH_MULTI="OFF"
fi

### verifico se il certificato e' cambiato ###
CertificateVerify

case "${TRANSLATE}" in
"crypt")
        Crypt $2 ${PUBLICKEY} $3 $4 $5
        ;;
"decrypt")
        Decrypt $2 ${PRIVATEKEY} $3
        ;;
"crypt_list_file")
        CryptListFile $2 ${PUBLICKEY} $3
        ;;
*)
        GetLog "[ERRORE] opzione non prevista"
        ;;
esac
