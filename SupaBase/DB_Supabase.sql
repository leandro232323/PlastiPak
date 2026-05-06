-- =========================================================
-- PLASTIPAK - BASE DE DATOS SUPABASE / POSTGRESQL
-- Sistema de pedidos y control de proceso de sellado
-- =========================================================

-- Limpieza opcional para desarrollo
-- CUIDADO: Esto borra las tablas si ya existen.
drop view if exists vista_reporte_turno;
drop view if exists vista_planilla_operario;

drop table if exists reportes_turno cascade;
drop table if exists registros_sellado cascade;
drop table if exists planilla_detalle cascade;
drop table if exists planillas_produccion cascade;
drop table if exists selladora_capacidades cascade;
drop table if exists selladoras cascade;
drop table if exists ordenes_produccion cascade;
drop table if exists pedido_detalle cascade;
drop table if exists pedidos cascade;
drop table if exists referencia_procesos cascade;
drop table if exists referencias cascade;
drop table if exists usuarios cascade;

drop type if exists rol_usuario cascade;
drop type if exists estado_referencia cascade;
drop type if exists tipo_producto cascade;
drop type if exists estado_pedido cascade;
drop type if exists destino_referencia cascade;
drop type if exists proceso_produccion cascade;
drop type if exists estado_orden cascade;
drop type if exists estado_produccion_referencia cascade;
drop type if exists estado_registro_sellado cascade;
drop type if exists turno_trabajo cascade;
drop type if exists estado_selladora cascade;


-- =========================================================
-- ENUMS
-- =========================================================

create type rol_usuario as enum (
  'vendedor',
  'lider_produccion',
  'auxiliar_produccion',
  'operario_sellador'
);

create type estado_referencia as enum (
  'activa',
  'inactiva'
);

create type tipo_producto as enum (
  'bolsa',
  'rollo',
  'lamina'
);

create type estado_pedido as enum (
  'borrador',
  'confirmado',
  'en_produccion',
  'finalizado',
  'cancelado'
);

create type destino_referencia as enum (
  'cliente_externo',
  'consumo_interno'
);

create type proceso_produccion as enum (
  'extrusion',
  'impresion',
  'refilado',
  'sellado'
);

create type estado_orden as enum (
  'por_programar',
  'pendiente_por_material',
  'en_proceso',
  'finalizada',
  'cancelada'
);

create type estado_produccion_referencia as enum (
  'pendiente_por_material',
  'en_produccion',
  'finalizada'
);

create type estado_registro_sellado as enum (
  'en_proceso',
  'finalizado'
);

create type turno_trabajo as enum (
  'manana',
  'tarde',
  'noche'
);

create type estado_selladora as enum (
  'activa',
  'inactiva'
);


-- =========================================================
-- TABLA: usuarios
-- Relaciona usuarios de Supabase Auth con roles del sistema
-- =========================================================

create table usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nombre varchar(120) not null,
  correo varchar(150) not null unique,
  rol rol_usuario not null,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now()
);


-- =========================================================
-- TABLA: referencias
-- Productos que la empresa puede vender o producir
-- =========================================================

create table referencias (
  id bigserial primary key,

  -- Información general
  codigo_completo varchar(100) not null unique,
  referencia_corta varchar(100),
  nombre varchar(150) not null,
  grupo varchar(100),
  estado estado_referencia not null default 'activa',
  descripcion text,
  codigo_barras varchar(100),
  presentacion varchar(100),
  unidad_medida varchar(50),
  costo numeric(12,2) default 0,
  impuesto numeric(5,2) default 0,

  -- Precios comerciales básicos
  precio_mayorista numeric(12,2) default 0,
  precio_distribuidor numeric(12,2) default 0,
  precio_lista numeric(12,2) default 0,

  -- Parámetros técnicos
  tipo_producto tipo_producto not null,
  materia_prima varchar(150) not null,
  color varchar(100),
  troquelado varchar(100),
  ancho numeric(10,2),
  fuelle_izquierdo numeric(10,2),
  fuelle_derecho numeric(10,2),
  alto numeric(10,2),
  fuelle_superior numeric(10,2),
  fuelle_fondo numeric(10,2),
  calibre numeric(10,2),
  tiene_impresion boolean default false,
  colores_impresion varchar(150),
  tipo_cliente varchar(100),
  tipo_impresion varchar(100),
  sellado varchar(100),
  tratado_cara varchar(100),
  medida varchar(100),

  creado_por uuid references usuarios(id),
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now()
);


-- =========================================================
-- TABLA: referencia_procesos
-- Procesos requeridos por cada referencia
-- =========================================================

create table referencia_procesos (
  id bigserial primary key,
  referencia_id bigint not null references referencias(id) on delete cascade,
  proceso proceso_produccion not null,
  creado_en timestamp with time zone not null default now(),

  constraint uq_referencia_proceso unique (referencia_id, proceso)
);


-- =========================================================
-- TABLA: pedidos
-- Creados por vendedor
-- =========================================================

create table pedidos (
  id bigserial primary key,
  numero_pedido varchar(50) not null unique,
  vendedor_id uuid not null references usuarios(id),
  cliente varchar(150),
  fecha_pedido date not null default current_date,
  fecha_entrega date not null,
  estado estado_pedido not null default 'borrador',
  observaciones text,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now(),

  constraint chk_fecha_entrega_minima
  check (fecha_entrega >= fecha_pedido + interval '15 days')
);


-- =========================================================
-- TABLA: pedido_detalle
-- Referencias agregadas al pedido
-- =========================================================

create table pedido_detalle (
  id bigserial primary key,
  pedido_id bigint not null references pedidos(id) on delete cascade,
  referencia_id bigint not null references referencias(id),
  cantidad_solicitada integer not null check (cantidad_solicitada > 0),
  valor_unitario numeric(12,2) not null check (valor_unitario >= 0),
  destino destino_referencia not null,
  estado_produccion estado_produccion_referencia not null default 'pendiente_por_material',
  creado_en timestamp with time zone not null default now(),

  constraint uq_pedido_referencia unique (pedido_id, referencia_id)
);


-- =========================================================
-- TABLA: ordenes_produccion
-- Creadas por líder de producción
-- =========================================================

create table ordenes_produccion (
  id bigserial primary key,
  numero_orden varchar(50) not null unique,
  pedido_id bigint not null references pedidos(id),
  pedido_detalle_id bigint not null references pedido_detalle(id),
  referencia_id bigint not null references referencias(id),
  lider_id uuid not null references usuarios(id),
  cantidad_programada integer not null check (cantidad_programada > 0),
  proceso_controlado proceso_produccion not null default 'sellado',
  estado estado_orden not null default 'por_programar',
  observaciones text,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now()
);


-- =========================================================
-- TABLA: selladoras
-- Máquinas existentes
-- =========================================================

create table selladoras (
  id bigserial primary key,
  nombre varchar(100) not null unique,
  tipo_sellado varchar(100) not null,
  tipos_referencias_permitidas text,
  estado estado_selladora not null default 'activa',
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now()
);


-- =========================================================
-- TABLA: selladora_capacidades
-- Capacidades específicas de cada selladora
-- =========================================================

create table selladora_capacidades (
  id bigserial primary key,
  selladora_id bigint not null references selladoras(id) on delete cascade,
  capacidad varchar(100) not null,
  creado_en timestamp with time zone not null default now(),

  constraint uq_selladora_capacidad unique (selladora_id, capacidad)
);


-- =========================================================
-- TABLA: planillas_produccion
-- Programación por selladora, fecha y turno
-- =========================================================

create table planillas_produccion (
  id bigserial primary key,
  fecha date not null,
  turno turno_trabajo not null,
  selladora_id bigint not null references selladoras(id),
  auxiliar_id uuid not null references usuarios(id),
  observaciones text,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now(),

  constraint uq_planilla_fecha_turno_selladora unique (fecha, turno, selladora_id)
);


-- =========================================================
-- TABLA: planilla_detalle
-- Órdenes asignadas a una planilla
-- =========================================================

create table planilla_detalle (
  id bigserial primary key,
  planilla_id bigint not null references planillas_produccion(id) on delete cascade,
  orden_id bigint not null references ordenes_produccion(id),
  secuencia integer not null check (secuencia > 0),
  cantidad_programada integer not null check (cantidad_programada > 0),
  observaciones text,
  creado_en timestamp with time zone not null default now(),

  constraint uq_planilla_orden unique (planilla_id, orden_id),
  constraint uq_planilla_secuencia unique (planilla_id, secuencia)
);


-- =========================================================
-- TABLA: registros_sellado
-- Registro operativo hecho por el operario/sellador
-- =========================================================

create table registros_sellado (
  id bigserial primary key,
  planilla_detalle_id bigint not null references planilla_detalle(id),
  orden_id bigint not null references ordenes_produccion(id),
  referencia_id bigint not null references referencias(id),
  selladora_id bigint not null references selladoras(id),
  operario_id uuid not null references usuarios(id),

  codigo_rollo varchar(100) not null,
  hora_inicio timestamp with time zone not null default now(),
  hora_finalizacion timestamp with time zone,
  cantidad_bolsas_producidas integer default 0 check (cantidad_bolsas_producidas >= 0),
  estado estado_registro_sellado not null default 'en_proceso',
  observaciones text,

  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now(),

  constraint chk_finalizacion_mayor_inicio
  check (
    hora_finalizacion is null
    or hora_finalizacion >= hora_inicio
  )
);


-- =========================================================
-- TABLA: reportes_turno
-- Reporte generado a partir de registros de sellado
-- =========================================================

create table reportes_turno (
  id bigserial primary key,
  fecha date not null,
  turno turno_trabajo not null,
  selladora_id bigint not null references selladoras(id),
  auxiliar_id uuid not null references usuarios(id),
  generado_en timestamp with time zone not null default now(),
  observaciones text,

  constraint uq_reporte_fecha_turno_selladora unique (fecha, turno, selladora_id)
);


-- =========================================================
-- FUNCIONES AUXILIARES
-- =========================================================

-- Actualiza automáticamente actualizado_en
create or replace function actualizar_fecha_modificacion()
returns trigger as $$
begin
  new.actualizado_en = now();
  return new;
end;
$$ language plpgsql;


-- Obtener rol del usuario autenticado
create or replace function obtener_rol_usuario()
returns rol_usuario as $$
  select rol
  from usuarios
  where id = auth.uid()
  limit 1;
$$ language sql stable;


-- Validar si el usuario tiene un rol específico
create or replace function tiene_rol(rol_requerido rol_usuario)
returns boolean as $$
  select exists (
    select 1
    from usuarios
    where id = auth.uid()
    and rol = rol_requerido
    and activo = true
  );
$$ language sql stable;


-- Validar si el usuario tiene alguno de varios roles
create or replace function tiene_alguno_de_roles(roles rol_usuario[])
returns boolean as $$
  select exists (
    select 1
    from usuarios
    where id = auth.uid()
    and rol = any(roles)
    and activo = true
  );
$$ language sql stable;


-- =========================================================
-- TRIGGERS actualizado_en
-- =========================================================

create trigger trg_usuarios_actualizado
before update on usuarios
for each row execute function actualizar_fecha_modificacion();

create trigger trg_referencias_actualizado
before update on referencias
for each row execute function actualizar_fecha_modificacion();

create trigger trg_pedidos_actualizado
before update on pedidos
for each row execute function actualizar_fecha_modificacion();

create trigger trg_ordenes_actualizado
before update on ordenes_produccion
for each row execute function actualizar_fecha_modificacion();

create trigger trg_selladoras_actualizado
before update on selladoras
for each row execute function actualizar_fecha_modificacion();

create trigger trg_planillas_actualizado
before update on planillas_produccion
for each row execute function actualizar_fecha_modificacion();

create trigger trg_registros_actualizado
before update on registros_sellado
for each row execute function actualizar_fecha_modificacion();


-- =========================================================
-- FUNCIÓN: confirmar pedido
-- Cambia pedido a en_produccion
-- =========================================================

create or replace function confirmar_pedido(p_pedido_id bigint)
returns void as $$
begin
  update pedidos
  set estado = 'en_produccion',
      actualizado_en = now()
  where id = p_pedido_id
    and vendedor_id = auth.uid()
    and estado in ('borrador', 'confirmado');

  if not found then
    raise exception 'No se pudo confirmar el pedido. Verifique permisos o estado.';
  end if;
end;
$$ language plpgsql security definer;


-- =========================================================
-- FUNCIÓN: finalizar registro de sellado
-- =========================================================

create or replace function finalizar_registro_sellado(
  p_registro_id bigint,
  p_cantidad_bolsas integer,
  p_observaciones text default null
)
returns void as $$
begin
  update registros_sellado
  set hora_finalizacion = now(),
      cantidad_bolsas_producidas = p_cantidad_bolsas,
      estado = 'finalizado',
      observaciones = coalesce(p_observaciones, observaciones),
      actualizado_en = now()
  where id = p_registro_id
    and operario_id = auth.uid()
    and estado = 'en_proceso';

  if not found then
    raise exception 'No se pudo finalizar el registro. Verifique permisos o estado.';
  end if;
end;
$$ language plpgsql security definer;


-- =========================================================
-- FUNCIÓN: generar reporte por turno
-- =========================================================

create or replace function generar_reporte_turno(
  p_fecha date,
  p_turno turno_trabajo,
  p_selladora_id bigint,
  p_observaciones text default null
)
returns bigint as $$
declare
  nuevo_reporte_id bigint;
begin
  insert into reportes_turno (
    fecha,
    turno,
    selladora_id,
    auxiliar_id,
    observaciones
  )
  values (
    p_fecha,
    p_turno,
    p_selladora_id,
    auth.uid(),
    p_observaciones
  )
  on conflict (fecha, turno, selladora_id)
  do update set
    generado_en = now(),
    auxiliar_id = auth.uid(),
    observaciones = excluded.observaciones
  returning id into nuevo_reporte_id;

  return nuevo_reporte_id;
end;
$$ language plpgsql security definer;


-- =========================================================
-- VISTA: planilla para operario
-- =========================================================

create or replace view vista_planilla_operario as
select
  pp.id as planilla_id,
  pp.fecha,
  pp.turno,
  s.id as selladora_id,
  s.nombre as selladora,
  pd.id as planilla_detalle_id,
  pd.secuencia,
  op.id as orden_id,
  op.numero_orden,
  p.numero_pedido,
  r.id as referencia_id,
  r.codigo_completo,
  r.referencia_corta,
  r.nombre as nombre_referencia,
  r.descripcion,
  r.materia_prima,
  r.sellado,
  r.ancho,
  r.alto,
  r.calibre,
  r.medida,
  pd.cantidad_programada
from planillas_produccion pp
join selladoras s on s.id = pp.selladora_id
join planilla_detalle pd on pd.planilla_id = pp.id
join ordenes_produccion op on op.id = pd.orden_id
join pedidos p on p.id = op.pedido_id
join referencias r on r.id = op.referencia_id
order by pp.fecha, pp.turno, s.nombre, pd.secuencia;


-- =========================================================
-- VISTA: reporte operativo por turno
-- =========================================================

create or replace view vista_reporte_turno as
select
  rs.id as registro_id,
  date(rs.hora_inicio) as fecha,
  pp.turno,
  s.nombre as selladora,
  u.nombre as operario,
  op.numero_orden,
  p.numero_pedido,
  r.codigo_completo,
  r.nombre as referencia,
  rs.codigo_rollo,
  rs.hora_inicio,
  rs.hora_finalizacion,
  rs.cantidad_bolsas_producidas,
  rs.estado
from registros_sellado rs
join usuarios u on u.id = rs.operario_id
join selladoras s on s.id = rs.selladora_id
join ordenes_produccion op on op.id = rs.orden_id
join pedidos p on p.id = op.pedido_id
join referencias r on r.id = rs.referencia_id
join planilla_detalle pd on pd.id = rs.planilla_detalle_id
join planillas_produccion pp on pp.id = pd.planilla_id
order by rs.hora_inicio desc;


-- =========================================================
-- ÍNDICES PARA BÚSQUEDA Y RENDIMIENTO
-- =========================================================

create index idx_referencias_codigo on referencias(codigo_completo);
create index idx_referencias_corta on referencias(referencia_corta);
create index idx_referencias_nombre on referencias(nombre);
create index idx_referencias_tipo_producto on referencias(tipo_producto);
create index idx_referencias_materia_prima on referencias(materia_prima);
create index idx_referencias_ancho on referencias(ancho);
create index idx_referencias_sellado on referencias(sellado);

create index idx_pedidos_vendedor on pedidos(vendedor_id);
create index idx_pedidos_estado on pedidos(estado);
create index idx_pedido_detalle_pedido on pedido_detalle(pedido_id);
create index idx_ordenes_estado on ordenes_produccion(estado);
create index idx_ordenes_pedido on ordenes_produccion(pedido_id);
create index idx_planillas_fecha_turno on planillas_produccion(fecha, turno);
create index idx_registros_operario on registros_sellado(operario_id);
create index idx_registros_estado on registros_sellado(estado);


-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================

alter table usuarios enable row level security;
alter table referencias enable row level security;
alter table referencia_procesos enable row level security;
alter table pedidos enable row level security;
alter table pedido_detalle enable row level security;
alter table ordenes_produccion enable row level security;
alter table selladoras enable row level security;
alter table selladora_capacidades enable row level security;
alter table planillas_produccion enable row level security;
alter table planilla_detalle enable row level security;
alter table registros_sellado enable row level security;
alter table reportes_turno enable row level security;


-- =========================================================
-- POLÍTICAS: usuarios
-- =========================================================

create policy "Usuarios pueden ver su propio perfil"
on usuarios for select
using (id = auth.uid());

create policy "Lider puede ver usuarios"
on usuarios for select
using (tiene_rol('lider_produccion'));

create policy "Lider puede crear usuarios"
on usuarios for insert
with check (tiene_rol('lider_produccion'));

create policy "Lider puede actualizar usuarios"
on usuarios for update
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: referencias
-- Vendedor puede consultar, pero no crear ni modificar.
-- Líder crea y modifica referencias.
-- Auxiliar y operario consultan.
-- =========================================================

create policy "Todos los roles pueden consultar referencias"
on referencias for select
using (
  tiene_alguno_de_roles(array[
    'vendedor',
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Lider puede crear referencias"
on referencias for insert
with check (tiene_rol('lider_produccion'));

create policy "Lider puede actualizar referencias"
on referencias for update
using (tiene_rol('lider_produccion'));

create policy "Lider puede eliminar referencias"
on referencias for delete
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: referencia_procesos
-- =========================================================

create policy "Todos pueden consultar procesos de referencia"
on referencia_procesos for select
using (
  tiene_alguno_de_roles(array[
    'vendedor',
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Lider puede administrar procesos de referencia"
on referencia_procesos for all
using (tiene_rol('lider_produccion'))
with check (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: pedidos
-- Vendedor crea sus pedidos.
-- Líder consulta pedidos enviados a producción.
-- =========================================================

create policy "Vendedor puede consultar sus pedidos"
on pedidos for select
using (
  vendedor_id = auth.uid()
  or tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion'
  ]::rol_usuario[])
);

create policy "Vendedor puede crear pedidos"
on pedidos for insert
with check (
  tiene_rol('vendedor')
  and vendedor_id = auth.uid()
);

create policy "Vendedor puede actualizar sus pedidos borrador"
on pedidos for update
using (
  tiene_rol('vendedor')
  and vendedor_id = auth.uid()
  and estado in ('borrador', 'confirmado')
);

create policy "Lider puede actualizar estado de pedidos"
on pedidos for update
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: pedido_detalle
-- =========================================================

create policy "Consultar detalle de pedidos segun rol"
on pedido_detalle for select
using (
  exists (
    select 1
    from pedidos p
    where p.id = pedido_detalle.pedido_id
    and (
      p.vendedor_id = auth.uid()
      or tiene_alguno_de_roles(array[
        'lider_produccion',
        'auxiliar_produccion'
      ]::rol_usuario[])
    )
  )
);

create policy "Vendedor puede agregar detalle a sus pedidos"
on pedido_detalle for insert
with check (
  tiene_rol('vendedor')
  and exists (
    select 1
    from pedidos p
    where p.id = pedido_detalle.pedido_id
    and p.vendedor_id = auth.uid()
    and p.estado in ('borrador', 'confirmado')
  )
);

create policy "Vendedor puede actualizar detalle de sus pedidos"
on pedido_detalle for update
using (
  tiene_rol('vendedor')
  and exists (
    select 1
    from pedidos p
    where p.id = pedido_detalle.pedido_id
    and p.vendedor_id = auth.uid()
    and p.estado in ('borrador', 'confirmado')
  )
);

create policy "Lider puede actualizar estado produccion de detalle"
on pedido_detalle for update
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: ordenes_produccion
-- =========================================================

create policy "Roles de produccion pueden consultar ordenes"
on ordenes_produccion for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Lider puede crear ordenes"
on ordenes_produccion for insert
with check (
  tiene_rol('lider_produccion')
  and lider_id = auth.uid()
);

create policy "Lider puede actualizar ordenes"
on ordenes_produccion for update
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: selladoras
-- Auxiliar gestiona selladoras existentes.
-- =========================================================

create policy "Roles de produccion pueden consultar selladoras"
on selladoras for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Auxiliar puede crear selladoras"
on selladoras for insert
with check (tiene_rol('auxiliar_produccion'));

create policy "Auxiliar puede actualizar selladoras"
on selladoras for update
using (tiene_rol('auxiliar_produccion'));

create policy "Lider puede actualizar selladoras"
on selladoras for update
using (tiene_rol('lider_produccion'));


-- =========================================================
-- POLÍTICAS: selladora_capacidades
-- =========================================================

create policy "Roles de produccion pueden consultar capacidades"
on selladora_capacidades for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Auxiliar puede administrar capacidades"
on selladora_capacidades for all
using (tiene_rol('auxiliar_produccion'))
with check (tiene_rol('auxiliar_produccion'));


-- =========================================================
-- POLÍTICAS: planillas_produccion
-- =========================================================

create policy "Produccion puede consultar planillas"
on planillas_produccion for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Auxiliar puede crear planillas"
on planillas_produccion for insert
with check (
  tiene_rol('auxiliar_produccion')
  and auxiliar_id = auth.uid()
);

create policy "Auxiliar puede actualizar planillas"
on planillas_produccion for update
using (tiene_rol('auxiliar_produccion'));


-- =========================================================
-- POLÍTICAS: planilla_detalle
-- =========================================================

create policy "Produccion puede consultar detalle de planillas"
on planilla_detalle for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion',
    'operario_sellador'
  ]::rol_usuario[])
);

create policy "Auxiliar puede asignar ordenes a planillas"
on planilla_detalle for insert
with check (tiene_rol('auxiliar_produccion'));

create policy "Auxiliar puede actualizar detalle de planillas"
on planilla_detalle for update
using (tiene_rol('auxiliar_produccion'));


-- =========================================================
-- POLÍTICAS: registros_sellado
-- Operario registra su trabajo.
-- Auxiliar y líder consultan.
-- =========================================================

create policy "Produccion puede consultar registros de sellado"
on registros_sellado for select
using (
  operario_id = auth.uid()
  or tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion'
  ]::rol_usuario[])
);

create policy "Operario puede crear registros de sellado"
on registros_sellado for insert
with check (
  tiene_rol('operario_sellador')
  and operario_id = auth.uid()
);

create policy "Operario puede actualizar sus registros en proceso"
on registros_sellado for update
using (
  tiene_rol('operario_sellador')
  and operario_id = auth.uid()
  and estado = 'en_proceso'
);


-- =========================================================
-- POLÍTICAS: reportes_turno
-- =========================================================

create policy "Lider y auxiliar pueden consultar reportes"
on reportes_turno for select
using (
  tiene_alguno_de_roles(array[
    'lider_produccion',
    'auxiliar_produccion'
  ]::rol_usuario[])
);

create policy "Auxiliar puede crear reportes"
on reportes_turno for insert
with check (
  tiene_rol('auxiliar_produccion')
  and auxiliar_id = auth.uid()
);

create policy "Auxiliar puede actualizar reportes"
on reportes_turno for update
using (tiene_rol('auxiliar_produccion'));


-- =========================================================
-- DATOS INICIALES DE SELLADORAS
-- La empresa maneja cinco selladoras según el alcance.
-- =========================================================

insert into selladoras (nombre, tipo_sellado, tipos_referencias_permitidas, estado)
values
('Selladora 1', 'sellado de fondo', 'bolsas y referencias compatibles con sellado de fondo', 'activa'),
('Selladora 2', 'sellado lateral', 'bolsas y referencias compatibles con sellado lateral', 'activa'),
('Selladora 3', 'sellado de fondo', 'bolsas y referencias compatibles con sellado de fondo', 'activa'),
('Selladora 4', 'sellado lateral', 'bolsas y referencias compatibles con sellado lateral', 'activa'),
('Selladora 5', 'mixta', 'referencias compatibles con sellado de fondo o lateral', 'activa');

insert into selladora_capacidades (selladora_id, capacidad)
select id, 'sellado de fondo'
from selladoras
where tipo_sellado in ('sellado de fondo', 'mixta');

insert into selladora_capacidades (selladora_id, capacidad)
select id, 'sellado lateral'
from selladoras
where tipo_sellado in ('sellado lateral', 'mixta');


-- =========================================================
-- DATOS DE PRUEBA OPCIONALES
-- Puedes borrarlos si no los necesitas.
-- Nota: los usuarios reales se crean con Supabase Auth.
-- =========================================================

insert into referencias (
  codigo_completo,
  referencia_corta,
  nombre,
  grupo,
  estado,
  descripcion,
  codigo_barras,
  presentacion,
  unidad_medida,
  costo,
  precio_lista,
  tipo_producto,
  materia_prima,
  color,
  troquelado,
  ancho,
  fuelle_izquierdo,
  fuelle_derecho,
  alto,
  calibre,
  tiene_impresion,
  sellado,
  tratado_cara,
  medida
)
values
(
  'BOL-AD-001',
  'AD001',
  'Bolsa alta densidad blanca',
  'Bolsas',
  'activa',
  'Bolsa en polietileno de alta densidad color blanco con sellado de fondo.',
  '770000000001',
  'Paquete',
  'unidad',
  50.00,
  90.50,
  'bolsa',
  'polietileno alta densidad',
  'blanco',
  'sin troquel',
  10.00,
  2.75,
  2.75,
  18.50,
  0.50,
  false,
  'sellado de fondo',
  'ninguno',
  'pulgadas'
);