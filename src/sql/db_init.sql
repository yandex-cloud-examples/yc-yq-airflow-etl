set vars.acc to :'acc';

select 'try to create account table...' as prompt;

create table accounts(
	id bigint primary key,
	num varchar(20) not null, 
	saldo numeric(10,2) not null,
	open_date timestamp not null
);

with series as (select generate_series(0, 10000) s)
insert into accounts (id, num, saldo, open_date)  
select series.s, lpad(series.s::varchar, 20, '0'), 0, now() from series;


select 'try to create payment table...' as prompt;
-- payment table
create table payments 
(id bigint not null, 
doc_num varchar(10) not null,
accdt bigint not null,
acckt bigint not null,
amount float not null,
payment_date timestamp not null,
descr varchar(64),
state varchar not null
) partition by range (payment_date);

alter table payments add constraint pk_payments primary key (id, payment_date);

create index idx_payments_accdt on payments(accdt);
create index idx_payments_acckt on payments(acckt);

alter table payments add constraint fk_payments_accdt foreign key (accdt) references accounts(id);
alter table payments add constraint fk_payments_acckt foreign key (acckt) references accounts(id);

select 'filling payment table' as prompt;

do $$ 
declare 
  cyear int;
  cmonth int;
  first_day date;
  next_day date;
  id bigint = 1;
  dt record;
  acc_num int = current_setting('vars.acc', true);
  cur_rnd int;
begin
    -- try to create data for five years since 2020/01
	for i in 0..60 loop
		cyear = 2020+floor(i/12);
		cmonth = i%12 + 1;
		first_day = make_date(cyear, cmonth, 1);
		next_day = date_add(first_day, '1 month'::interval);
		execute format('create table payments_y%sm%s 
			partition of payments for values from (date''%s'') to (date''%s'');',
			cyear, lpad(cmonth::varchar, 2, '0'), first_day, next_day); 
		for dt in select generate_series(first_day, next_day - '1 second'::interval, '1 minute'::interval) loop
		  cur_rnd = random() * acc_num;
		  insert into payments (id, doc_num, accdt, acckt, amount, payment_date, descr, state)
    		values(id, id::varchar, cur_rnd, acc_num - cur_rnd, cur_rnd, dt.generate_series, 'payment '||id, 'done');
		  id = id + 1;
    	end loop;
	end loop;
end
$$;

select 'PostgreSQL step finished' as prompt;