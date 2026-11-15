import os
import warnings

import mysql.connector
import pandas as pd
import streamlit as st
from dotenv import load_dotenv

# Carga las variables del archivo .env (si existe) para que os.getenv las encuentre
load_dotenv()

# --------------------------------------------------------------------------
# Conexión (las credenciales vienen de variables de entorno, no del código)
# --------------------------------------------------------------------------
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "simulador_f1"),
}

# Las versiones nuevas de mysql-connector avisan que stored_results() va a cambiar
# de forma. Funciona igual: ocultamos el aviso para no llenar la consola.
warnings.filterwarnings("ignore", message=".*stored_results.*")

# Códigos de error de la base que mostramos con un mensaje claro
ERROR_CHECK = (3819, 4025)   # CHECK fallido (MySQL / MariaDB): el presupuesto quedaría negativo
ERROR_DUPLICADO = 1062       # UNIQUE fallido


def conectar():
    """Abre una conexión nueva a la base."""
    return mysql.connector.connect(**DB_CONFIG)


def consultar(sql, params=()):
    """Ejecuta un SELECT y devuelve una lista de diccionarios."""
    conn = conectar()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params)
        return cur.fetchall()
    finally:
        conn.close()


def llamar_procedimiento(nombre, params):
    """
    Ejecuta un procedimiento de la base y devuelve el mensaje que responde
    (los procedimientos terminan con SELECT '...' AS resultado).
    """
    conn = conectar()
    try:
        cur = conn.cursor()
        cur.callproc(nombre, params)
        mensaje = "Operación realizada"
        for resultado in cur.stored_results():
            fila = resultado.fetchone()
            if fila:
                mensaje = fila[0]
        conn.commit()
        return mensaje
    finally:
        conn.close()


# --------------------------------------------------------------------------
# Acceso: iniciar sesión y crear cuenta
# --------------------------------------------------------------------------
def buscar_jugador(nombre, clave):
    """Devuelve la partida del usuario si el nombre y la contraseña son correctos."""
    filas = consultar(
        """
        SELECT u.nombre_usuario, p.id_partida, e.nombre AS escuderia
        FROM usuario u
        JOIN partida p   ON p.id_usuario   = u.id_usuario
        JOIN escuderia e ON e.id_escuderia = p.id_escuderia
        WHERE u.nombre_usuario = %s AND u.contrasena = SHA2(%s, 256)
        """,
        (nombre, clave),
    )
    return filas[0] if filas else None


def crear_cuenta(nombre, clave, id_escuderia):
    """
    Crea el usuario y su partida en una sola transacción.
    La partida arranca con el presupuesto inicial de la temporada (lo toma de la base).
    """
    conn = conectar()
    try:
        conn.start_transaction()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO usuario (nombre_usuario, contrasena) VALUES (%s, SHA2(%s, 256))",
            (nombre, clave),
        )
        id_usuario = cur.lastrowid
        cur.execute(
            """
            INSERT INTO partida (presupuesto, estado, id_escuderia, id_usuario, id_temporada)
            SELECT presupuesto_inicial, 0, %s, %s, id_temporada
            FROM temporada
            ORDER BY anio DESC
            LIMIT 1
            """,
            (id_escuderia, id_usuario),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def entrar(jugador):
    """Guarda en la sesión solo los datos del jugador que inició sesión."""
    st.session_state["id_partida"] = jugador["id_partida"]
    st.session_state["usuario"] = jugador["nombre_usuario"]
    st.session_state["escuderia"] = jugador["escuderia"]


def cerrar_sesion():
    for clave in list(st.session_state.keys()):
        del st.session_state[clave]


def pantalla_acceso():
    """Pantalla de inicio: iniciar sesión o crear una cuenta nueva."""
    tab_login, tab_registro = st.tabs(["Iniciar sesión", "Crear cuenta"])

    with tab_login:
        with st.form("form_login"):
            nombre = st.text_input("Usuario")
            clave = st.text_input("Contraseña", type="password")
            if st.form_submit_button("Entrar", type="primary"):
                jugador = buscar_jugador(nombre.strip(), clave)
                if jugador:
                    entrar(jugador)
                    st.rerun()
                else:
                    st.error("Usuario o contraseña incorrectos.")

    with tab_registro:
        escuderias = consultar("SELECT id_escuderia, nombre, pais FROM escuderia ORDER BY nombre")
        por_id = {e["id_escuderia"]: e for e in escuderias}
        with st.form("form_registro"):
            nombre = st.text_input("Elegí un nombre de usuario")
            clave = st.text_input("Contraseña (mínimo 6 caracteres)", type="password")
            clave2 = st.text_input("Repetí la contraseña", type="password")
            id_escuderia = st.selectbox(
                "Escudería que vas a dirigir",
                list(por_id),
                format_func=lambda i: f'{por_id[i]["nombre"]} ({por_id[i]["pais"]})',
                index=None,
                placeholder="Seleccionar escudería...",
            )
            st.caption("Tu escudería arranca sin pilotos y con el presupuesto inicial de la temporada.")
            if st.form_submit_button("Crear cuenta y empezar", type="primary"):
                nombre = nombre.strip()
                if not nombre or len(clave) < 6:
                    st.error("Completá el usuario y una contraseña de al menos 6 caracteres.")
                elif clave != clave2:
                    st.error("Las contraseñas no coinciden.")
                elif id_escuderia is None:
                    st.error("Elegí la escudería que vas a dirigir.")
                else:
                    try:
                        crear_cuenta(nombre, clave, id_escuderia)
                        entrar(buscar_jugador(nombre, clave))
                        st.rerun()
                    except mysql.connector.Error as e:
                        print("Error al crear la cuenta:", e)
                        if e.errno == ERROR_DUPLICADO:
                            st.error("Ese nombre de usuario ya existe. Elegí otro.")
                        else:
                            st.error("No se pudo crear la cuenta. Intentá de nuevo.")


# --------------------------------------------------------------------------
# Acciones del juego
# --------------------------------------------------------------------------
def contratar_piloto(id_partida, id_piloto):
    """
    Registra el contrato y descuenta el sueldo, en una sola transacción.
    Si el saldo no alcanza, el CHECK de la base rechaza el UPDATE y se hace ROLLBACK.
    """
    conn = conectar()
    try:
        conn.start_transaction()
        cur = conn.cursor()
        # Solo se puede contratar un piloto libre (sin escudería en la semilla)
        cur.execute(
            """
            INSERT INTO contrato (id_partida, id_piloto, sueldo_pactado)
            SELECT %s, id_piloto, sueldo_pedido
            FROM piloto
            WHERE id_piloto = %s AND id_escuderia IS NULL
            """,
            (id_partida, id_piloto),
        )
        if cur.rowcount != 1:
            raise ValueError("Ese piloto no está disponible en el mercado.")
        cur.execute(
            """
            UPDATE partida p
            JOIN piloto pl ON pl.id_piloto = %s
            SET p.presupuesto = p.presupuesto - pl.sueldo_pedido
            WHERE p.id_partida = %s
            """,
            (id_piloto, id_partida),
        )
        conn.commit()
        return "Contrato firmado."
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def comprar_componente(id_partida, id_componente, id_carrera):
    """La compra la valida y la ejecuta la base (sp_comprar_componente)."""
    return llamar_procedimiento("sp_comprar_componente", (id_partida, id_componente, id_carrera))


def correr_carrera(id_partida):
    """La base elige la siguiente carrera, calcula los tiempos y los guarda (sp_correr_carrera)."""
    return llamar_procedimiento("sp_correr_carrera", (id_partida,))


def reiniciar_temporada(id_partida):
    """
    Empieza la temporada de nuevo, en una sola transacción:
    borra resultados, compras y contratos de la partida, devuelve el presupuesto
    al inicial de la temporada y la marca como en curso.
    """
    conn = conectar()
    try:
        conn.start_transaction()
        cur = conn.cursor()
        cur.execute("DELETE FROM resultado WHERE id_partida = %s", (id_partida,))
        cur.execute("DELETE FROM compra WHERE id_partida = %s", (id_partida,))
        cur.execute("DELETE FROM contrato WHERE id_partida = %s", (id_partida,))
        cur.execute(
            """
            UPDATE partida p
            JOIN temporada t ON t.id_temporada = p.id_temporada
            SET p.presupuesto = t.presupuesto_inicial, p.estado = 0
            WHERE p.id_partida = %s
            """,
            (id_partida,),
        )
        conn.commit()
        return "Temporada reiniciada: presupuesto restaurado y partida limpia."
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# --------------------------------------------------------------------------
# Consultas para mostrar (posiciones y puntos salen de las vistas)
# --------------------------------------------------------------------------
def pilotos_de_partida(id_partida):
    return consultar(
        """
        SELECT pl.nombre AS piloto, pl.habilidad, ct.sueldo_pactado
        FROM contrato ct
        JOIN piloto pl ON pl.id_piloto = ct.id_piloto
        WHERE ct.id_partida = %s
        ORDER BY pl.habilidad DESC
        """,
        (id_partida,),
    )


def pilotos_libres(id_partida):
    """Anti-join: pilotos libres que esta partida todavía no contrató."""
    return consultar(
        """
        SELECT pl.id_piloto, pl.nombre, pl.habilidad, pl.sueldo_pedido
        FROM piloto pl
        LEFT JOIN contrato ct ON ct.id_piloto = pl.id_piloto AND ct.id_partida = %s
        WHERE pl.id_escuderia IS NULL AND ct.id_contrato IS NULL
        ORDER BY pl.habilidad DESC
        """,
        (id_partida,),
    )


def proxima_carrera(id_partida):
    """La siguiente carrera del calendario que la partida todavía no corrió (o None)."""
    filas = consultar(
        """
        SELECT ca.id_carrera, ca.orden, ca.nombre, ci.nombre AS circuito
        FROM carrera ca
        JOIN partida p   ON p.id_temporada = ca.id_temporada
        JOIN circuito ci ON ci.id_circuito = ca.id_circuito
        WHERE p.id_partida = %s
          AND ca.orden = (SELECT COUNT(DISTINCT r.id_carrera) + 1
                          FROM resultado r WHERE r.id_partida = %s)
        """,
        (id_partida, id_partida),
    )
    return filas[0] if filas else None


def carreras_corridas(id_partida):
    return consultar(
        """
        SELECT DISTINCT ca.id_carrera, ca.orden, ca.nombre
        FROM resultado r
        JOIN carrera ca ON ca.id_carrera = r.id_carrera
        WHERE r.id_partida = %s
        ORDER BY ca.orden
        """,
        (id_partida,),
    )


def calendario(id_partida):
    """Las carreras de la temporada, con su estado para esta partida."""
    # En DATE_FORMAT los % van dobles (%%): la consulta usa parámetros con %s,
    # y mysql-connector tomaría un % solo como un parámetro más.
    return consultar(
        """
        SELECT ca.orden, ca.nombre, ci.nombre AS circuito, ci.pais,
               DATE_FORMAT(ca.fecha, '%%d/%%m/%%Y') AS fecha,
               CASE
                 WHEN EXISTS (SELECT 1 FROM resultado r
                              WHERE r.id_partida = p.id_partida AND r.id_carrera = ca.id_carrera)
                   THEN '✅ Corrida'
                 WHEN ca.orden = (SELECT COUNT(DISTINCT r.id_carrera) + 1
                                  FROM resultado r WHERE r.id_partida = p.id_partida)
                   THEN '▶ Próxima'
                 ELSE 'Pendiente'
               END AS estado
        FROM carrera ca
        JOIN partida p   ON p.id_temporada = ca.id_temporada
        JOIN circuito ci ON ci.id_circuito = ca.id_circuito
        WHERE p.id_partida = %s
        ORDER BY ca.orden
        """,
        (id_partida,),
    )


def resultado_carrera(id_partida, id_carrera):
    return consultar(
        """
        SELECT v.posicion, pl.nombre AS piloto,
               CASE WHEN v.es_jugador = 1 THEN CONCAT(ep.nombre, ' (vos)') ELSE e.nombre END AS equipo,
               v.tiempo, v.puntos, v.es_jugador
        FROM v_puntos v
        JOIN piloto pl ON pl.id_piloto = v.id_piloto
        LEFT JOIN escuderia e ON e.id_escuderia = pl.id_escuderia   -- escudería del rival
        JOIN partida pa    ON pa.id_partida   = v.id_partida
        JOIN escuderia ep  ON ep.id_escuderia = pa.id_escuderia     -- escudería del jugador
        WHERE v.id_partida = %s AND v.id_carrera = %s
        ORDER BY v.posicion
        """,
        (id_partida, id_carrera),
    )


def campeonato_pilotos(id_partida):
    return consultar(
        """
        SELECT pl.nombre AS piloto,
               CASE WHEN v.es_jugador = 1 THEN CONCAT(ep.nombre, ' (vos)') ELSE e.nombre END AS equipo,
               v.es_jugador,
               SUM(v.puntos) AS puntos,
               SUM(CASE WHEN v.posicion = 1 THEN 1 ELSE 0 END) AS victorias,
               -- Posición en el campeonato: más puntos primero; si empatan, más victorias
               RANK() OVER (ORDER BY SUM(v.puntos) DESC,
                                     SUM(CASE WHEN v.posicion = 1 THEN 1 ELSE 0 END) DESC) AS posicion
        FROM v_puntos v
        JOIN piloto pl ON pl.id_piloto = v.id_piloto
        LEFT JOIN escuderia e ON e.id_escuderia = pl.id_escuderia   -- escudería del rival
        JOIN partida pa    ON pa.id_partida   = v.id_partida
        JOIN escuderia ep  ON ep.id_escuderia = pa.id_escuderia     -- escudería del jugador
        WHERE v.id_partida = %s
        GROUP BY pl.id_piloto, pl.nombre, v.es_jugador, e.nombre, ep.nombre
        ORDER BY posicion
        """,
        (id_partida,),
    )


# --------------------------------------------------------------------------
# Botones: se ejecutan antes de redibujar la pantalla
# --------------------------------------------------------------------------
def ejecutar(accion, *args):
    """Ejecuta una acción y guarda un mensaje simple para el usuario."""
    try:
        mensaje = accion(*args)
        es_error = mensaje.startswith(("Saldo", "Compra cancelada", "Error", "La temporada"))
        st.session_state["mensaje"] = ("error" if es_error else "ok", mensaje)
    except mysql.connector.Error as e:
        print("Error de la base:", e)   # el detalle técnico queda en la consola, no en pantalla
        if e.errno in ERROR_CHECK:
            texto = "Saldo insuficiente: la operación se canceló."
        elif e.errno == ERROR_DUPLICADO:
            texto = "Esa operación ya estaba registrada: se canceló."
        else:
            texto = "No se pudo completar la operación. No se modificó nada."
        st.session_state["mensaje"] = ("error", texto)
    except ValueError as e:
        st.session_state["mensaje"] = ("error", str(e))


def al_contratar():
    ss = st.session_state
    ejecutar(contratar_piloto, ss["id_partida"], ss["id_piloto_sel"])
    ss["id_piloto_sel"] = None   # vuelve el select a "Seleccionar piloto..."


def al_comprar():
    ss = st.session_state
    ejecutar(comprar_componente, ss["id_partida"], ss["id_componente_sel"], ss["id_carrera_compra"])
    ss["id_componente_sel"] = None   # vuelve el select a "Seleccionar componente..."


def al_correr():
    ejecutar(correr_carrera, st.session_state["id_partida"])


def al_reiniciar():
    ejecutar(reiniciar_temporada, st.session_state["id_partida"])
    st.session_state["confirmar_reinicio"] = False


# --------------------------------------------------------------------------
# Interfaz
# --------------------------------------------------------------------------
def dinero(valor):
    return f"$ {valor:,.0f}".replace(",", ".")


def tabla(filas, columnas, columnas_dinero=(), estilo_fila=None, config_columnas=None):
    """
    Muestra una tabla con los títulos de columna en español.
    Solo muestra las columnas que están en 'columnas' (las demás quedan ocultas).
    Las columnas de 'columnas_dinero' se muestran con formato $ (ej: $ 5.000.000).
    """
    if not filas:
        st.caption("Sin datos para mostrar.")
        return
    df = pd.DataFrame(filas)[list(columnas)]
    for col in columnas_dinero:
        df[col] = df[col].apply(dinero)
    df = df.rename(columns=columnas)
    if estilo_fila:
        # Aplica el mismo estilo a todas las celdas de la fila
        df = df.style.apply(lambda fila: [estilo_fila(fila)] * len(fila), axis=1)
    # config_columnas: cómo dibujar alguna columna (por ejemplo, como barra de progreso)
    st.dataframe(df, hide_index=True, column_config=config_columnas)


def estilo_proxima(fila):
    """Resalta la fila de la próxima carrera del calendario."""
    if fila["Estado"] == "▶ Próxima":
        return "background-color: rgba(255, 75, 75, 0.15); font-weight: bold"
    return ""


# Estilo para todo lo que es "tuyo" (tus pilotos, tu fila en el ranking): violeta transparente
ESTILO_MIO = "background-color: rgba(155, 89, 182, 0.10); font-weight: bold"

# La habilidad va de 1 a 100: se muestra como barra, con el número al lado
BARRA_HABILIDAD = {"Habilidad": st.column_config.ProgressColumn(
    "Habilidad", min_value=0, max_value=100, format="%d")}


def estilo_mis_pilotos(fila):
    """Resalta las filas de los pilotos del jugador (su equipo termina en '(vos)')."""
    if "(vos)" in fila["Equipo"]:
        return ESTILO_MIO
    return ""


def estilo_mi_usuario(fila):
    """Resalta la fila del usuario que inició sesión en el ranking."""
    if fila["Usuario"] == st.session_state["usuario"]:
        return ESTILO_MIO
    return ""


def main():
    st.set_page_config(page_title="Simulador F1", page_icon="🏎️", layout="wide")
    st.title("Simulador F1 · Gestión de escudería")

    # Si nadie inició sesión, se muestra la pantalla de acceso y nada más
    if "id_partida" not in st.session_state:
        try:
            pantalla_acceso()
        except mysql.connector.Error as e:
            print("Error de conexión:", e)
            st.error("No se pudo conectar a la base de datos. Revisá que esté iniciada y las variables DB_*.")
        st.stop()

    id_partida = st.session_state["id_partida"]
    st.sidebar.markdown(f'👤 **{st.session_state["usuario"]}**')
    st.sidebar.markdown(f'🏎️ {st.session_state["escuderia"]}')
    st.sidebar.button("Cerrar sesión", on_click=cerrar_sesion)

    # Mensaje de la última acción: notificación flotante que desaparece sola
    mensaje = st.session_state.pop("mensaje", None)
    if mensaje:
        if mensaje[0] == "ok":
            st.toast(mensaje[1], icon="✅")
        else:
            st.toast(mensaje[1], icon="⚠️", duration="long")   # los errores duran más, para que se lean

    partida = consultar(
        """
        SELECT p.presupuesto, p.estado,
               (SELECT COUNT(*) FROM carrera ca WHERE ca.id_temporada = p.id_temporada) AS total_carreras,
               (SELECT COUNT(DISTINCT r.id_carrera) FROM resultado r WHERE r.id_partida = p.id_partida) AS corridas
        FROM partida p
        WHERE p.id_partida = %s
        """,
        (id_partida,),
    )[0]
    finalizada = partida["estado"] == 1
    pilotos = pilotos_de_partida(id_partida)
    siguiente = proxima_carrera(id_partida)

    m0, m1, m2, m3 = st.columns(4)
    m0.metric("Escudería", st.session_state["escuderia"])
    m1.metric("Presupuesto disponible", dinero(partida["presupuesto"]))
    m2.metric("Carreras corridas", f'{partida["corridas"]} / {partida["total_carreras"]}')
    # La próxima carrera la calcula proxima_carrera() con una consulta; None = temporada terminada
    m3.metric("Próxima carrera", siguiente["nombre"] if siguiente else "Temporada terminada")

    # Lugar fijo para el aviso: siempre existe (aunque esté vacío) para que las pestañas
    # no cambien de posición; si cambian, Streamlit vuelve a abrir "Mi equipo"
    zona_aviso = st.container()
    if not finalizada and len(pilotos) < 2:
        zona_aviso.info("👋 Paso 1: contratá tus 2 pilotos en la pestaña **Mercado y tienda**. "
                "Después podés comprar componentes y correr las carreras.")

    tab_equipo, tab_mercado, tab_carreras, tab_ranking = st.tabs(
        ["Mi equipo", "Mercado y tienda", "Carreras", "Ranking"]
    )

    # ---------------- Mi equipo ----------------
    with tab_equipo:
        st.subheader("Mis pilotos")
        if pilotos:
            tabla(pilotos, {"piloto": "Piloto", "habilidad": "Habilidad", "sueldo_pactado": "Sueldo pactado"},
                  columnas_dinero=["sueldo_pactado"],
                  config_columnas=BARRA_HABILIDAD)
        else:
            st.caption("Todavía no contrataste pilotos.")

        st.subheader("Componentes comprados")
        compras = consultar(
            """
            SELECT co.tipo, co.durabilidad, ca.orden AS desde_carrera, c.precio_pagado,
                   -- Activo = todavía resta segundos en la próxima carrera
                   -- (misma condición de durabilidad que sp_correr_carrera)
                   CASE WHEN prox.orden - ca.orden >= 0 AND prox.orden - ca.orden < co.durabilidad
                        THEN '🟢 Activo' ELSE '⚫ Gastado' END AS estado
            FROM compra c
            JOIN componentes co ON co.id_componentes = c.id_componentes
            JOIN carrera ca     ON ca.id_carrera     = c.id_carrera
            -- Número de la próxima carrera de esta partida (las corridas + 1)
            JOIN (SELECT COUNT(DISTINCT id_carrera) + 1 AS orden
                  FROM resultado WHERE id_partida = %s) prox
            WHERE c.id_partida = %s
            ORDER BY ca.orden
            """,
            (id_partida, id_partida),
        )
        if compras:
            tabla(compras, {"tipo": "Componente", "durabilidad": "Durabilidad (carreras)",
                            "desde_carrera": "Desde la carrera", "precio_pagado": "Precio pagado",
                            "estado": "Estado"},
                  columnas_dinero=["precio_pagado"])
        else:
            st.caption("Todavía no compraste componentes.")

    # ---------------- Mercado y tienda ----------------
    with tab_mercado:
        if finalizada:
            st.info("La temporada terminó: ya no se puede contratar ni comprar.")
        else:
            st.subheader("Contratar pilotos")
            nombres = " y ".join(p["piloto"] for p in pilotos)
            if len(pilotos) >= 2:
                st.success(f"Tu equipo está completo: {nombres}.")
            else:
                if pilotos:
                    st.caption(f"Ya contrataste a {nombres}. Te falta 1 piloto.")
                libres = pilotos_libres(id_partida)
                tabla(libres, {"nombre": "Piloto", "habilidad": "Habilidad", "sueldo_pedido": "Sueldo pedido"},
                      columnas_dinero=["sueldo_pedido"], config_columnas=BARRA_HABILIDAD)
                por_id = {p["id_piloto"]: p for p in libres}
                # index=None: arranca sin nada elegido, para no contratar por error
                piloto_elegido = st.selectbox(
                    "Piloto libre",
                    list(por_id),
                    format_func=lambda i: f'{por_id[i]["nombre"]} · habilidad {por_id[i]["habilidad"]} · '
                                          f'{dinero(por_id[i]["sueldo_pedido"])}',
                    index=None,
                    placeholder="Seleccionar piloto...",
                    key="id_piloto_sel",
                )
                st.button("Contratar", type="primary", on_click=al_contratar,
                          disabled=piloto_elegido is None)

            st.divider()
            st.subheader("Tienda de componentes")
            st.caption(f'Lo que compres se instala para la próxima carrera: {siguiente["orden"]}. {siguiente["nombre"]}.')
            st.session_state["id_carrera_compra"] = siguiente["id_carrera"]
            componentes = consultar(
                "SELECT id_componentes, tipo, costo, rendimiento_extra, durabilidad "
                "FROM componentes ORDER BY id_componentes"
            )
            tabla(componentes, {"tipo": "Componente", "costo": "Costo",
                                "rendimiento_extra": "Segundos que resta", "durabilidad": "Durabilidad (carreras)"},
                  columnas_dinero=["costo"])
            por_id_comp = {c["id_componentes"]: c for c in componentes}
            # index=None: arranca sin nada elegido, para no comprar por error
            componente_elegido = st.selectbox(
                "Componente",
                list(por_id_comp),
                # Ej: "Aerodinámica · (−0.8 s) · $ 3.000.000" (:g saca los ceros de más)
                format_func=lambda i: f'{por_id_comp[i]["tipo"]} · '
                                      f'(−{float(por_id_comp[i]["rendimiento_extra"]):g} s) · '
                                      f'{dinero(por_id_comp[i]["costo"])}',
                index=None,
                placeholder="Seleccionar componente...",
                key="id_componente_sel",
            )
            st.button("Comprar", type="primary", on_click=al_comprar,
                      disabled=componente_elegido is None)

    # ---------------- Carreras ----------------
    with tab_carreras:
        st.subheader("Calendario de la temporada")
        tabla(calendario(id_partida), {"orden": "Nº", "nombre": "Carrera", "circuito": "Circuito",
                                       "pais": "País", "fecha": "Fecha", "estado": "Estado"},
              estilo_fila=estilo_proxima)
        st.divider()

        if not finalizada:
            if len(pilotos) < 2:
                st.warning("Necesitás 2 pilotos contratados para correr.")
            # El botón dice qué carrera se va a correr (el calendario de arriba muestra el resto)
            st.button(f'🏁 Correr carrera {siguiente["orden"]}: {siguiente["nombre"]}',
                      type="primary", on_click=al_correr, disabled=len(pilotos) < 2, width="stretch")
        else:
            campeon = campeonato_pilotos(id_partida)[0]
            if campeon["es_jugador"] == 1:
                st.success(f'🏆 ¡{campeon["piloto"]} es el campeón con {int(campeon["puntos"])} puntos!')
            else:
                st.info(f'🏆 {campeon["piloto"]} ({campeon["equipo"]}) ganó el campeonato con '
                        f'{int(campeon["puntos"])} puntos.')

        corridas = carreras_corridas(id_partida)

        # Resultado de la última carrera corrida: posición y puntos salen de v_puntos
        if corridas:
            ultima = corridas[-1]
            st.subheader(f'Última carrera: {ultima["nombre"]}')
            mis_resultados = [f for f in resultado_carrera(id_partida, ultima["id_carrera"])
                              if f["es_jugador"] == 1]
            columnas = st.columns(len(mis_resultados))
            for col, fila in zip(columnas, mis_resultados):
                # Sin puntos (fuera del top 10): la flecha se ve gris en lugar de verde
                col.metric(fila["piloto"], f'{fila["posicion"]}° puesto', f'+{int(fila["puntos"])} pts',
                           delta_color="normal" if fila["puntos"] > 0 else "off")
            st.divider()

        if corridas:
            st.subheader("Campeonato de pilotos")
            tabla(campeonato_pilotos(id_partida),
                  {"posicion": "Pos", "piloto": "Piloto", "equipo": "Equipo",
                   "puntos": "Puntos", "victorias": "Victorias"},
                  estilo_fila=estilo_mis_pilotos)

            st.subheader("Resultados por carrera")
            for pestana, carrera in zip(st.tabs([c["nombre"] for c in corridas]), corridas):
                with pestana:
                    tabla(resultado_carrera(id_partida, carrera["id_carrera"]),
                          {"posicion": "Pos", "piloto": "Piloto", "equipo": "Equipo",
                           "tiempo": "Tiempo (s)", "puntos": "Puntos"},
                          estilo_fila=estilo_mis_pilotos)

        st.divider()
        # Zona de peligro: recuadro con título en rojo para que se note que la acción es destructiva
        with st.container(border=True):
            st.markdown("#### :red[⚠️ Zona de peligro: reiniciar temporada]")
            st.caption("Borra tus resultados, compras y contratos, y devuelve el presupuesto inicial. No se puede deshacer.")
            st.checkbox("Entiendo que se borrará mi temporada actual", key="confirmar_reinicio")
            st.button(
                "🔄 Reiniciar temporada",
                on_click=al_reiniciar,
                disabled=not st.session_state.get("confirmar_reinicio", False),
            )

    # ---------------- Ranking ----------------
    with tab_ranking:
        st.subheader("Ranking de usuarios")
        # El puesto lo calcula la base con RANK(), igual que las posiciones de las carreras
        ranking = consultar(
            "SELECT RANK() OVER (ORDER BY puntos_totales DESC) AS puesto, "
            "nombre_usuario, escuderia, puntos_totales "
            "FROM v_ranking_usuarios ORDER BY puesto"
        )
        # Busca la fila del usuario que inició sesión (no calcula nada, solo la encuentra)
        mi_fila = next((r for r in ranking if r["nombre_usuario"] == st.session_state["usuario"]), None)
        if mi_fila:
            st.info(f'Vas en el puesto {mi_fila["puesto"]} con {int(mi_fila["puntos_totales"])} puntos.')
        tabla(ranking, {"puesto": "Puesto", "nombre_usuario": "Usuario",
                        "escuderia": "Escudería", "puntos_totales": "Puntos"},
              estilo_fila=estilo_mi_usuario)


if __name__ == "__main__":
    main()
