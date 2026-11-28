alter table public.muestreos_proceso
  add column if not exists presentacion text not null default '6 oz',
  add column if not exists cuadrilla text not null default '',
  add column if not exists muestreados text not null default '',
  add column if not exists peso double precision,
  add column if not exists frutos_larva integer not null default 0;
