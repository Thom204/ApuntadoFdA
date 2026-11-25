extends GutTest
## Cada ventana de escritorio puede ser un jugador distinto con `-- --perfil=<nombre>`:
## el token de sesión se guarda en un archivo por perfil.


func test_sin_perfil_usa_el_archivo_de_siempre() -> void:
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray()), "user://apuntado_session.cfg")


func test_con_perfil_cada_uno_tiene_su_archivo() -> void:
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray(["--perfil=3"])), "user://apuntado_session_3.cfg")
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray(["--otro", "--perfil=ana"])), "user://apuntado_session_ana.cfg")


func test_el_perfil_no_puede_salirse_de_la_carpeta() -> void:
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray(["--perfil=../../x"])), "user://apuntado_session_x.cfg")


func test_un_perfil_vacio_o_invalido_usa_el_archivo_de_siempre() -> void:
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray(["--perfil="])), "user://apuntado_session.cfg")
	assert_eq(ClientNetworkEndpoint.session_path_for(PackedStringArray(["--perfil=../"])), "user://apuntado_session.cfg")
