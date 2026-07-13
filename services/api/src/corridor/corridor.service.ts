import { Injectable, NotFoundException } from '@nestjs/common';
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

  create(dto: CreateCorridorDto): Promise<Corridor> {
    return this.prisma.corridor.create({
      data: {
        originCity: dto.originCity,
        destCity: dto.destCity,
        pricePerSeat: dto.pricePerSeat,
        active: true,
      },
    });
  }

  async update(id: string, dto: UpdateCorridorDto): Promise<Corridor> {
    const existing = await this.prisma.corridor.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException('الممر غير موجود.');
    }
    return this.prisma.corridor.update({ where: { id }, data: dto });
  }
}
