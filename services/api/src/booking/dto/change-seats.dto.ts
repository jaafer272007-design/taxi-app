import { IsInt, Max, Min } from 'class-validator';

/**
 * Change how many seats an existing booking holds.
 *
 * The same 1..4 bound as `CreateBookingDto` — and now it actually binds. While
 * a rider could book the same trip twice, two bookings of 4 put 8 seats behind
 * one person and the cap meant nothing.
 */
export class ChangeSeatsDto {
  @IsInt({ message: 'عدد المقاعد يجب أن يكون رقماً.' })
  @Min(1, { message: 'مقعد واحد على الأقل.' })
  @Max(4, { message: '4 مقاعد كحد أقصى للحجز.' })
  seatCount!: number;
}
