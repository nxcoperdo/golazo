/// Validaciones de formularios (las mismas reglas que aplica el backend).
class Validators {
  const Validators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^3\d{9}$');

  static String? required(String? v, [String label = 'Este campo']) =>
      (v == null || v.trim().isEmpty) ? '$label es obligatorio' : null;

  static String? name(String? v) =>
      (v == null || v.trim().length < 2) ? 'Escribe tu nombre' : null;

  static String? email(String? v) =>
      (v != null && _email.hasMatch(v.trim())) ? null : 'Correo no válido';

  /// Celular colombiano: 10 dígitos que empiezan por 3.
  static String? phone(String? v) =>
      (v != null && _phone.hasMatch(v.trim())) ? null : 'Celular de 10 dígitos que empiece por 3';

  static String? password(String? v) =>
      (v != null && v.length >= 8) ? null : 'Mínimo 8 caracteres';
}
