-- =====================================================
-- SCRIPT SUPABASE / POSTGRESQL PARA PLASTIPAK
-- Base de datos relacional basada en los requerimientos corregidos.
--
-- Roles funcionales:
-- - vendedor
-- - lider_produccion
-- - auxiliar_produccion
-- - operario
--
-- Flujo:
-- Referencia -> Pedido -> Orden de produccion -> Planilla de produccion
-- -> Registro de sellado -> Reporte por turno
-- =====================================================

-- =====================================================
-- 0. EXTENSIONES NECESARIAS
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- 1. LIMPIEZA PARA REEJECUTAR EL SCRIPT
-- OJO: Esto borra las tablas si ya existen.
-- =====================================================

drop table if exists registros_sellado cascade;
drop table if exists planilla_tareas cascade;
drop table if exists planillas_produccion cascade;
drop table if exists ordenes_produccion cascade;
drop table if exists pedido_items cascade;
drop table if exists pedidos cascade;
drop table if exists referencia_precios cascade;
drop table if exists referencias cascade;
drop table if exists selladoras cascade;
drop table if exists usuarios cascade;

drop type if exists rol_usuario cascade;
drop type if exists estado_referencia cascade;
drop type if exists destino_pedido_item cascade;
drop type if exists estado_produccion_item cascade;
drop type if exists estado_pedido cascade;
drop type if exists proceso_controlado cascade;
drop type if exists estado_orden cascade;
drop type if exists estado_selladora cascade;
drop type if exists turno_produccion cascade;
drop type if exists estado_planilla cascade;
drop type if exists estado_tarea cascade;
drop type if exists estado_registro_sellado cascade;

-- =====================================================
-- 2. TIPOS ENUM
-- =====================================================

create type rol_usuario as enum (
  'vendedor',
  'lider_produccion',
  'auxiliar_produccion',
  'operario'
);

create type estado_referencia as enum (
  'activa',
  'inactiva'
);

create type destino_pedido_item as enum (
  'cliente_externo',
  'consumo_interno'
);

create type estado_produccion_item as enum (
  'pendiente_por_material',
  'en_produccion',
  'finalizada'
);

create type estado_pedido as enum (
  'en_produccion',
  'finalizado'
);

create type proceso_controlado as enum (
  'sellado'
);

create type estado_orden as enum (
  'pendiente_por_material',
  'por_programar',
  'programada',
  'en_proceso',
  'finalizada'
);

create type estado_selladora as enum (
  'activa',
  'inactiva'
);

create type turno_produccion as enum (
  'turno_1',
  'turno_2',
  'turno_3'
);

create type estado_planilla as enum (
  'activa',
  'cerrada'
);

create type estado_tarea as enum (
  'pendiente',
  'en_proceso',
  'finalizada'
);

create type estado_registro_sellado as enum (
  'en_proceso',
  'finalizado'
);

-- =====================================================
-- 3. FUNCION PARA UPDATED_AT
-- =====================================================

create or replace function actualizar_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- =====================================================
-- 4. TABLA USUARIOS
-- =====================================================

create table usuarios (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  correo text not null unique,
  password_hash text not null,
  rol rol_usuario not null,
  estado boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_usuarios_updated_at
before update on usuarios
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 5. TABLA REFERENCIAS
-- Esta tabla representa los productos que se pueden vender o producir.
-- El lider de produccion crea las referencias.
-- =====================================================

create table referencias (
  id uuid primary key default gen_random_uuid(),

  referencia text not null unique,
  referencia_corta text not null,
  nombre text not null,
  grupo text,
  estado estado_referencia not null default 'activa',
  descripcion text,
  codigo_barras text,
  presentacion text,
  unidad_medida text not null default 'unidades',

  costo numeric(14,4),
  impuesto numeric(14,4),
  valor_unitario numeric(14,4) not null default 0,

  -- Parametros tecnicos visibles en la imagen enviada
  tipo_producto text not null,
  materia_prima text not null,
  color text,
  troquelado text,
  ancho numeric(10,2) not null,
  fuelle_izquierdo numeric(10,2),
  fuelle_derecho numeric(10,2),
  alto numeric(10,2),
  fuelle_superior numeric(10,2),
  fuelle_fondo numeric(10,2),
  calibre numeric(10,2),
  impresion boolean not null default false,
  colores jsonb not null default '[]'::jsonb,
  tipo_cliente text,
  tipo_impresion text,
  sellado text not null,
  tratado_cara text,
  medida text not null,

  -- Procesos requeridos por referencia
  requiere_extrusion boolean not null default false,
  requiere_impresion boolean not null default false,
  requiere_refilado boolean not null default false,
  requiere_sellado boolean not null default true,

  creada_por uuid references usuarios(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_referencias_updated_at
before update on referencias
for each row
execute function actualizar_updated_at();

-- Precios por categoria de cada referencia
create table referencia_precios (
  id uuid primary key default gen_random_uuid(),
  referencia_id uuid not null references referencias(id) on delete cascade,
  categoria text not null,
  precio numeric(14,4) not null default 0,
  incluye_impuesto boolean default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_referencia_precios_updated_at
before update on referencia_precios
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 6. TABLA PEDIDOS
-- El vendedor crea pedidos con referencias existentes.
-- Al confirmar, el pedido pasa directamente a produccion.
-- =====================================================

create table pedidos (
  id uuid primary key default gen_random_uuid(),
  numero_pedido text not null unique,
  vendedor_id uuid not null references usuarios(id),
  fecha_toma date not null default current_date,
  fecha_entrega_pactada date not null,
  estado_pedido estado_pedido not null default 'en_produccion',
  total_pedido numeric(14,4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_fecha_entrega_minima
  check (fecha_entrega_pactada >= fecha_toma + interval '15 days')
);

create trigger trg_pedidos_updated_at
before update on pedidos
for each row
execute function actualizar_updated_at();

create table pedido_items (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references pedidos(id) on delete cascade,
  referencia_id uuid not null references referencias(id),

  referencia text not null,
  referencia_corta text,
  nombre_referencia text not null,
  descripcion_referencia text,

  cantidad_solicitada numeric(14,2) not null check (cantidad_solicitada > 0),
  valor_unitario numeric(14,4) not null default 0,
  subtotal numeric(14,4) not null default 0,

  destino destino_pedido_item not null,
  estado_produccion estado_produccion_item not null default 'en_produccion',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_pedido_items_updated_at
before update on pedido_items
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 7. TABLA ORDENES DE PRODUCCION
-- Creadas por el lider de produccion sobre una referencia especifica del pedido.
-- =====================================================

create table ordenes_produccion (
  id uuid primary key default gen_random_uuid(),
  numero_orden text not null unique,

  pedido_id uuid not null references pedidos(id),
  pedido_item_id uuid not null references pedido_items(id),
  referencia_id uuid not null references referencias(id),

  referencia text,
  referencia_corta text,
  nombre_referencia text,

  cantidad_programada numeric(14,2) not null check (cantidad_programada > 0),
  proceso_controlado proceso_controlado not null default 'sellado',
  estado_orden estado_orden not null default 'por_programar',

  creada_por uuid not null references usuarios(id),

  selladora_id uuid,
  planilla_id uuid,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_ordenes_produccion_updated_at
before update on ordenes_produccion
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 8. TABLA SELLADORAS
-- La empresa tiene 5 selladoras base.
-- =====================================================

create table selladoras (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  numero int not null unique,
  sellado_fondo boolean not null default true,
  sellado_lateral boolean not null default false,
  tipos_referencia_permitidos jsonb not null default '[]'::jsonb,
  estado estado_selladora not null default 'activa',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_selladoras_updated_at
before update on selladoras
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 9. TABLAS PLANILLAS DE PRODUCCION Y TAREAS
-- El auxiliar de produccion programa ordenes en selladoras.
-- =====================================================

create table planillas_produccion (
  id uuid primary key default gen_random_uuid(),
  codigo_planilla text not null unique,
  fecha date not null,
  turno turno_produccion not null,
  selladora_id uuid not null references selladoras(id),
  creada_por uuid not null references usuarios(id),
  estado_planilla estado_planilla not null default 'activa',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_planilla_fecha_turno_selladora
  unique (fecha, turno, selladora_id)
);

create trigger trg_planillas_produccion_updated_at
before update on planillas_produccion
for each row
execute function actualizar_updated_at();

create table planilla_tareas (
  id uuid primary key default gen_random_uuid(),
  planilla_id uuid not null references planillas_produccion(id) on delete cascade,

  secuencia int not null check (secuencia > 0),
  orden_produccion_id uuid not null references ordenes_produccion(id),
  pedido_id uuid not null references pedidos(id),
  referencia_id uuid not null references referencias(id),

  referencia text,
  nombre_referencia text,
  cantidad_programada numeric(14,2) not null check (cantidad_programada > 0),
  grupo_similar text,
  estado_tarea estado_tarea not null default 'pendiente',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint uq_tarea_planilla_secuencia unique (planilla_id, secuencia)
);

create trigger trg_planilla_tareas_updated_at
before update on planilla_tareas
for each row
execute function actualizar_updated_at();

alter table ordenes_produccion
add constraint fk_orden_selladora
foreign key (selladora_id) references selladoras(id);

alter table ordenes_produccion
add constraint fk_orden_planilla
foreign key (planilla_id) references planillas_produccion(id);

-- =====================================================
-- 10. TABLA REGISTROS DE SELLADO
-- El operario registra rollo, inicio, fin y cantidad producida.
-- =====================================================

create table registros_sellado (
  id uuid primary key default gen_random_uuid(),

  planilla_id uuid not null references planillas_produccion(id),
  tarea_id uuid not null references planilla_tareas(id),
  orden_produccion_id uuid not null references ordenes_produccion(id),
  pedido_id uuid not null references pedidos(id),
  referencia_id uuid not null references referencias(id),
  selladora_id uuid not null references selladoras(id),
  operario_id uuid not null references usuarios(id),

  codigo_rollo text not null,
  fecha date not null,
  turno turno_produccion not null,

  hora_inicio timestamptz not null,
  hora_fin timestamptz,
  cantidad_bolsas_producidas numeric(14,2),

  estado_registro estado_registro_sellado not null default 'en_proceso',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_registro_finalizado
  check (
    estado_registro = 'en_proceso'
    or (
      estado_registro = 'finalizado'
      and hora_fin is not null
      and cantidad_bolsas_producidas is not null
    )
  )
);

create trigger trg_registros_sellado_updated_at
before update on registros_sellado
for each row
execute function actualizar_updated_at();

-- =====================================================
-- 11. VISTA PARA REPORTE POR TURNO
-- El reporte no necesita tabla propia; sale de registros_sellado.
-- =====================================================

create or replace view vw_reporte_turno as
select
  rs.id as registro_id,
  rs.fecha,
  rs.turno,
  s.codigo as codigo_selladora,
  s.nombre as selladora,
  u.nombre as operario,
  op.numero_orden,
  p.numero_pedido,
  r.referencia,
  r.nombre as nombre_referencia,
  rs.codigo_rollo,
  rs.hora_inicio,
  rs.hora_fin,
  rs.cantidad_bolsas_producidas,
  rs.estado_registro
from registros_sellado rs
join selladoras s on s.id = rs.selladora_id
join usuarios u on u.id = rs.operario_id
join ordenes_produccion op on op.id = rs.orden_produccion_id
join pedidos p on p.id = rs.pedido_id
join referencias r on r.id = rs.referencia_id;

-- =====================================================
-- 12. INDICES
-- =====================================================

create index idx_usuarios_rol on usuarios(rol);
create index idx_usuarios_estado on usuarios(estado);

create index idx_referencias_referencia_corta on referencias(referencia_corta);
create index idx_referencias_nombre on referencias(nombre);
create index idx_referencias_tipo_producto on referencias(tipo_producto);
create index idx_referencias_materia_prima on referencias(materia_prima);
create index idx_referencias_ancho on referencias(ancho);
create index idx_referencias_color on referencias(color);
create index idx_referencias_sellado on referencias(sellado);
create index idx_referencias_estado on referencias(estado);

create index idx_pedidos_vendedor on pedidos(vendedor_id);
create index idx_pedidos_fecha_toma on pedidos(fecha_toma desc);
create index idx_pedidos_fecha_entrega on pedidos(fecha_entrega_pactada);
create index idx_pedidos_estado on pedidos(estado_pedido);

create index idx_pedido_items_pedido on pedido_items(pedido_id);
create index idx_pedido_items_referencia on pedido_items(referencia_id);
create index idx_pedido_items_estado on pedido_items(estado_produccion);

create index idx_ordenes_pedido on ordenes_produccion(pedido_id);
create index idx_ordenes_referencia on ordenes_produccion(referencia_id);
create index idx_ordenes_estado on ordenes_produccion(estado_orden);
create index idx_ordenes_selladora on ordenes_produccion(selladora_id);

create index idx_planillas_fecha_turno on planillas_produccion(fecha, turno);
create index idx_planillas_selladora on planillas_produccion(selladora_id);

create index idx_tareas_planilla on planilla_tareas(planilla_id);
create index idx_tareas_orden on planilla_tareas(orden_produccion_id);

create index idx_registros_fecha_turno on registros_sellado(fecha, turno);
create index idx_registros_selladora_fecha_turno on registros_sellado(selladora_id, fecha, turno);
create index idx_registros_operario_fecha on registros_sellado(operario_id, fecha);
create index idx_registros_orden on registros_sellado(orden_produccion_id);
create index idx_registros_estado on registros_sellado(estado_registro);

-- =====================================================
-- 13. FUNCIONES BASICAS PARA TOTAL DEL PEDIDO
-- =====================================================

create or replace function recalcular_total_pedido(p_pedido_id uuid)
returns void as $$
begin
  update pedidos
  set total_pedido = coalesce((
    select sum(subtotal)
    from pedido_items
    where pedido_id = p_pedido_id
  ), 0)
  where id = p_pedido_id;
end;
$$ language plpgsql;

create or replace function trg_recalcular_total_pedido()
returns trigger as $$
begin
  if tg_op = 'DELETE' then
    perform recalcular_total_pedido(old.pedido_id);
    return old;
  else
    perform recalcular_total_pedido(new.pedido_id);
    return new;
  end if;
end;
$$ language plpgsql;

create trigger trg_pedido_items_recalcular_total_insert
after insert on pedido_items
for each row
execute function trg_recalcular_total_pedido();

create trigger trg_pedido_items_recalcular_total_update
after update on pedido_items
for each row
execute function trg_recalcular_total_pedido();

create trigger trg_pedido_items_recalcular_total_delete
after delete on pedido_items
for each row
execute function trg_recalcular_total_pedido();

-- =====================================================
-- 14. DATOS INICIALES
-- =====================================================

-- Usuarios de prueba
insert into usuarios (nombre, correo, password_hash, rol, estado)
values
  ('Usuario Vendedor', 'vendedor@plastipak.com', 'CAMBIAR_POR_HASH_BCRYPT', 'vendedor', true),
  ('Usuario Lider Produccion', 'liderproduccion@plastipak.com', 'CAMBIAR_POR_HASH_BCRYPT', 'lider_produccion', true),
  ('Usuario Auxiliar Produccion', 'auxiliarproduccion@plastipak.com', 'CAMBIAR_POR_HASH_BCRYPT', 'auxiliar_produccion', true),
  ('Usuario Operario', 'operario@plastipak.com', 'CAMBIAR_POR_HASH_BCRYPT', 'operario', true);

-- Selladoras base
insert into selladoras (
  codigo,
  nombre,
  numero,
  sellado_fondo,
  sellado_lateral,
  tipos_referencia_permitidos,
  estado
)
values
  ('SELL-01', 'Selladora 1', 1, true, true,  '["B-Bolsa"]'::jsonb, 'activa'),
  ('SELL-02', 'Selladora 2', 2, true, false, '["B-Bolsa"]'::jsonb, 'activa'),
  ('SELL-03', 'Selladora 3', 3, true, false, '["B-Bolsa"]'::jsonb, 'activa'),
  ('SELL-04', 'Selladora 4', 4, true, false, '["B-Bolsa"]'::jsonb, 'activa'),
  ('SELL-05', 'Selladora 5', 5, true, false, '["B-Bolsa"]'::jsonb, 'activa');

-- Referencia de ejemplo basada en la imagen enviada
insert into referencias (
  referencia,
  referencia_corta,
  nombre,
  grupo,
  estado,
  descripcion,
  codigo_barras,
  presentacion,
  unidad_medida,
  costo,
  impuesto,
  valor_unitario,

  tipo_producto,
  materia_prima,
  color,
  troquelado,
  ancho,
  fuelle_izquierdo,
  fuelle_derecho,
  alto,
  fuelle_superior,
  fuelle_fondo,
  calibre,
  impresion,
  colores,
  tipo_cliente,
  tipo_impresion,
  sellado,
  tratado_cara,
  medida,

  requiere_extrusion,
  requiere_impresion,
  requiere_refilado,
  requiere_sellado,

  creada_por
)
select
  'BADBLFRA010.00102.75D02.75L018.5C0.5F0',
  'BADBLFRA1012.75D2.75L18.5C0.5F0',
  '10 KG BANCA NUEVA [PUL]',
  'BABL',
  'activa',
  'Bolsa Polietileno Alta Densidad Blanco Franela Ancho 10 Fuelle Izquierdo 2.75 Fuelle Derecho 2.75 Alto 18.5 Calibre 0.5 PULGADAS Sellado Fondo',
  '770000018348',
  null,
  'unidades',
  53.6911,
  null,
  90.5,

  'B-Bolsa',
  'AD-Polietileno Alta Densidad',
  'BL-Blanco',
  'FR-Franela',
  10.00,
  2.75,
  2.75,
  18.50,
  null,
  null,
  0.50,
  false,
  '[]'::jsonb,
  null,
  null,
  'F-Sellado Fondo',
  '0-Ninguno',
  'PUL-PULGADAS',

  true,
  false,
  false,
  true,

  u.id
from usuarios u
where u.rol = 'lider_produccion'
limit 1;

-- Precios de la referencia de ejemplo
insert into referencia_precios (
  referencia_id,
  categoria,
  precio,
  incluye_impuesto
)
select
  r.id,
  'mayorista',
  0,
  false
from referencias r
where r.referencia = 'BADBLFRA010.00102.75D02.75L018.5C0.5F0';

insert into referencia_precios (
  referencia_id,
  categoria,
  precio,
  incluye_impuesto
)
select
  r.id,
  'mostrador',
  90.5,
  true
from referencias r
where r.referencia = 'BADBLFRA010.00102.75D02.75L018.5C0.5F0';

-- =====================================================
-- 15. CONSULTAS DE VERIFICACION
-- =====================================================

select 'Base de datos Supabase/PostgreSQL creada correctamente para PlastiPak' as resultado;

select
  nombre,
  correo,
  rol,
  estado
from usuarios
order by rol;

select
  codigo,
  nombre,
  numero,
  sellado_fondo,
  sellado_lateral,
  estado
from selladoras
order by numero;

select
  referencia,
  referencia_corta,
  nombre,
  tipo_producto,
  materia_prima,
  ancho,
  alto,
  calibre,
  sellado
from referencias;