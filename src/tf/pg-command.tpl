! psql --version && echo "psql not installed" || \
  psql -h ${HOST} -q -p 6432 -U "${USERNAME}" -d ${USERNAME} \
  -v acc=${ACC_NUM} -f "../sql/db_init.sql"