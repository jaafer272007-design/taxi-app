import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Corridor } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCorridorDto } from './dto/create-corridor.dto';
import { UpdateCorridorDto } from './dto/update-corridor.dto';

@Injectable()
export class CorridorService {
  constructor(private readonly prisma: PrismaService) {}

  list(): Promise<Corridor[]> {
    return this.prisma.corridor.findMany({ orderBy: [{ originCity: 'asc' }, { destCity: 'asc' }] });
  }

  findById(id: string): Promise<Corridor | null> {
    return this.prisma.corridor.findUnique({ where: { id } });
  }

  async create(dto: CreateCorridorDto): Promise<Corridor> {
    this.assertDistinct(dto.originCity, dto.destCity);
    this.assertPriceBand(
      dto.minPricePerSeat,
      dto.suggestedPricePerSeat,
      dto.maxPricePerSeat,
    );
    await this.assertPairFree(dto.originCity, dto.destCity);
    try {
      return await this.prisma.corridor.create({
        data: {
          originCity: dto.originCity,
          destCity: dto.destCity,
          suggestedPricePerSeat: dto.suggestedPricePerSeat,
          minPricePerSeat: dto.minPricePerSeat,
          maxPricePerSeat: dto.maxPricePerSeat,
          active: true,
        },
      });
    } catch (err) {
      throw this.mapDuplicate(err);
    }
  }

  async update(id: string, dto: UpdateCorridorDto): Promise<Corridor> {
    const existing = await this.prisma.corridor.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException('الممر غير موجود.');
    }

    // A partial price update has to be validated against the MERGED row, not
    // against the payload: raising only `minPricePerSeat` can still push it past
    // a `suggestedPricePerSeat` that isn't in this request at all.
    this.assertPriceBand(
      dto.minPricePerSeat ?? existing.minPricePerSeat,
      dto.suggestedPricePerSeat ?? existing.suggestedPricePerSeat,
      dto.maxPricePerSeat ?? existing.maxPricePerSeat,
    );

    // If the city pair is being changed, re-validate it (distinct + not already
    // taken by ANOTHER corridor). Price / active toggles skip these checks.
    const changingPair = dto.originCity !== undefined || dto.destCity !== undefined;
    if (changingPair) {
      const originCity = dto.originCity ?? existing.originCity;
      const destCity = dto.destCity ?? existing.destCity;
      this.assertDistinct(originCity, destCity);
      await this.assertPairFree(originCity, destCity, id);
    }

    try {
      return await this.prisma.corridor.update({ where: { id }, data: dto });
    } catch (err) {
      throw this.mapDuplicate(err);
    }
  }

  private assertDistinct(originCity: string, destCity: string): void {
    if (originCity === destCity) {
      throw new BadRequestException(
        'لا يمكن أن تكون مدينة الانطلاق والوصول متطابقتين.',
      );
    }
  }

  /**
   * The corridor's pricing invariant: `0 < min <= suggested <= max`.
   *
   * Positivity is already covered per-field by the DTOs; it is re-asserted here
   * because `update` merges the payload with the stored row, and a row written
   * before this rule existed must not slip through. The messages name WHICH
   * bound is wrong so the admin panel can point at the offending field.
   */
  private assertPriceBand(min: number, suggested: number, max: number): void {
    if (min < 1 || suggested < 1 || max < 1) {
      throw new BadRequestException('الأسعار يجب أن تكون أكبر من صفر.');
    }
    if (min > max) {
      throw new BadRequestException('أدنى سعر يجب أن يكون أقل من أعلى سعر أو مساوياً له.');
    }
    if (suggested < min) {
      throw new BadRequestException('السعر المقترح يجب ألّا يقل عن أدنى سعر.');
    }
    if (suggested > max) {
      throw new BadRequestException('السعر المقترح يجب ألّا يزيد على أعلى سعر.');
    }
  }

  /** Reject a directed (origin, dest) pair that already has a corridor. */
  private async assertPairFree(
    originCity: string,
    destCity: string,
    exceptId?: string,
  ): Promise<void> {
    const clash = await this.prisma.corridor.findFirst({
      where: {
        originCity,
        destCity,
        ...(exceptId ? { id: { not: exceptId } } : {}),
      },
      select: { id: true },
    });
    if (clash) {
      throw new ConflictException('يوجد ممر لهذا المسار مسبقاً.');
    }
  }

  /** Backstop for the DB unique index (races): map P2002 to a friendly 409. */
  private mapDuplicate(err: unknown): unknown {
    if ((err as { code?: string })?.code === 'P2002') {
      return new ConflictException('يوجد ممر لهذا المسار مسبقاً.');
    }
    return err;
  }
}
