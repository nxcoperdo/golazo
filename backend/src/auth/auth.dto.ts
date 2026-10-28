import { Equals, IsBoolean, IsEmail, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';

/** Celular colombiano: 10 dígitos que empiezan por 3. Solo dato de contacto. */
export const PHONE_REGEX = /^3\d{9}$/;

export class RegisterDto {
  @IsString() @Length(2, 80) name!: string;
  @IsEmail() @MaxLength(254) email!: string;
  @IsString() @MinLength(8) @MaxLength(128) password!: string;
  @Matches(PHONE_REGEX, { message: 'El celular debe tener 10 dígitos y empezar por 3' })
  phone!: string;
  /** true = se registra como dueño de cancha. El rol admin nunca se asigna desde la API. */
  @IsOptional() @IsBoolean() asOwner?: boolean;
  /** Autorización de datos y términos (Ley 1581): obligatoria para crear la cuenta. */
  @Equals(true, { message: 'Debes aceptar los términos y la política de privacidad' })
  acceptTerms!: boolean;
}

export class ConsentDto {
  @Equals(true, { message: 'Debes aceptar los términos y la política de privacidad' })
  accept!: boolean;
}

export class LoginDto {
  @IsEmail() email!: string;
  @IsString() @MaxLength(128) password!: string;
}

export class GoogleDto {
  @IsString() @MinLength(10) idToken!: string;
  @IsOptional()
  @Matches(PHONE_REGEX, { message: 'El celular debe tener 10 dígitos y empezar por 3' })
  phone?: string;
}

export class UpdateProfileDto {
  @IsOptional() @IsString() @Length(2, 80) name?: string;
  @IsOptional()
  @Matches(PHONE_REGEX, { message: 'El celular debe tener 10 dígitos y empezar por 3' })
  phone?: string;
}

export class ChangePasswordDto {
  @IsString() @MaxLength(128) current!: string;
  @IsString() @MinLength(8) @MaxLength(128) next!: string;
}

export class ForgotPasswordDto {
  @IsEmail() email!: string;
}

export class ResetPasswordDto {
  @IsString() @MinLength(20) @MaxLength(200) token!: string;
  @IsString() @MinLength(8) @MaxLength(128) next!: string;
}

export class VerifyEmailDto {
  @IsString() @MinLength(20) @MaxLength(200) token!: string;
}

export class DeleteAccountDto {
  @IsOptional() @IsString() @MaxLength(128) password?: string;
}

export class RefreshDto {
  @IsString() @MinLength(20) refreshToken!: string;
}
