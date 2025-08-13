create table if not exists samples (
  sample_id serial primary key,
  external_id text unique,
  sex text check (sex in ('male','female') or sex is null),
  ancestry text,
  notes text,
  created_at timestamp default now()
);

create table if not exists variants (
  variant_id bigserial primary key,
  chrom text not null,
  pos integer not null,
  ref text not null,
  alt text not null,
  rsid text,
  gene text,
  impact text,
  info jsonb default {}::jsonb,
  constraint uq_variant unique (chrom, pos, ref, alt)
);

create table if not exists genotypes (
  sample_id int references samples(sample_id) on delete cascade,
  variant_id bigint references variants(variant_id) on delete cascade,
  gt text,
  gq int, dp int,
  ad int[],
  fmt jsonb default {}::jsonb,
  primary key (sample_id, variant_id)
);

create index if not exists idx_variants_chrpos on variants (chrom, pos);
create index if not exists idx_variants_gene on variants (gene);
create index if not exists idx_genotypes_sample on genotypes (sample_id);
create index if not exists idx_genotypes_variant on genotypes (variant_id);
