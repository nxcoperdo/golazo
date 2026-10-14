import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

const toBool = ({ value }: { value: unknown }) => (value === 'true' ? true : value === 'false' ? false : value);

export class ListCourtsQuery {
  @IsOptional() @IsString() @MaxLength(60) city?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) maxPrice?: number;
  @IsOptional() @Transform(toBool) @IsBoolean() covered?: boolean;
  /** Si llegan lat y lng, se ordena por cercanía. */
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0.1) @Max(500) radiusKm?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

export class AvailabilityQuery {
  /** YYYY-MM-DD en hora de Colombia. */
  @IsString() @Length(10, 10) date!: string;
}

export class CreateCourtDto {
  @IsString() @Length(3, 80) name!: string;
  @IsOptional() @IsString() @MaxLength(1000) description?: string;
  @IsString() @Length(2, 60) city!: string;
  @IsString() @Length(3, 160) address!: string;
  @IsNumber() @Min(-90) @Max(90) lat!: number;
  @IsNumber() @Min(-180) @Max(180) lng!: number;
  @IsBoolean() covered!: boolean;
  @IsInt() @Min(1000) @Max(1_000_000) pricePerHour!: number;
  @IsInt() @Min(0) @Max(23) openHour!: number;
  @IsInt() @Min(1) @Max(24) closeHour!: number;
  @IsBoolean() requiresDeposit!: boolean;
  @IsOptional() @IsInt() @Min(10) @Max(100) depositPercent?: number;
}

export class UpdateCourtDto {
  @IsOptional() @IsString() @Length(3, 80) name?: string;
  @IsOptional() @IsString() @MaxLength(1000) description?: string;
  @IsOptional() @IsString() @Length(2, 60) city?: string;
  @IsOptional() @IsString() @Length(3, 160) address?: string;
  @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number;
  @IsOptional() @IsBoolean() covered?: boolean;
  @IsOptional() @IsInt() @Min(1000) @Max(1_000_000) pricePerHour?: number;
  @IsOptional() @IsInt() @Min(0) @Max(23) openHour?: number;
  @IsOptional() @IsInt() @Min(1) @Max(24) closeHour?: number;
  @IsOptional() @IsBoolean() requiresDeposit?: boolean;
  @IsOptional() @IsInt() @Min(10) @Max(100) depositPercent?: number;
}

export class PaymentMethodDto {
  @IsString() @Length(2, 40) label!: string;
  @IsString() @Length(3, 60) account!: string;
  @IsString() @Length(2, 80) holder!: string;
}

export class PaymentMethodsDto {
  @IsArray() @ArrayMaxSize(5) @ValidateNested({ each: true }) @Type(() => PaymentMethodDto)
  methods!: PaymentMethodDto[];
}
