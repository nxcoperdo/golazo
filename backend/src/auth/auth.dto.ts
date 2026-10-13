import { IsEmail, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';

/** Celular colombiano: 10 dígitos que empiezan por 3. Solo dato de contacto. */
export const PHONE_REGEX = /^3\d{9}$/;

export class RegisterDto {
  @IsString() @Length(2, 80) name!: string;
  @IsEmail() @MaxLength(254) email!: string;
  @IsString() @MinLength(8) @MaxLength(128) password!: string;
  @Matches(PHONE_REGEX, { message: 'El celular debe tener 10 dígitos y empezar por 3' })
  phone!: string;
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

export class RefreshDto {
  @IsString() @MinLength(20) refreshToken!: string;
}
