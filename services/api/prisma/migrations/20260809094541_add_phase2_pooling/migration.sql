-- CreateEnum
CREATE TYPE "SeatRequestStatus" AS ENUM ('PENDING', 'MATCHED', 'CANCELLED', 'DECLINED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "PoolStatus" AS ENUM ('FORMING', 'CLAIMED', 'RAISE_PENDING', 'EXPIRED');

-- CreateEnum
CREATE TYPE "RaiseResponse" AS ENUM ('ACCEPTED', 'DECLINED');

-- CreateEnum
CREATE TYPE "PoolRaiseOutcome" AS ENUM ('ACCEPTED', 'FAILED');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "NotificationType" ADD VALUE 'POOL_CLAIMED';
ALTER TYPE "NotificationType" ADD VALUE 'POOL_EXPIRED';
ALTER TYPE "NotificationType" ADD VALUE 'POOL_RAISE_PROPOSED';
ALTER TYPE "NotificationType" ADD VALUE 'POOL_RAISE_RESOLVED';

-- CreateTable
CREATE TABLE "SeatRequest" (
    "id" TEXT NOT NULL,
    "riderId" TEXT NOT NULL,
    "corridorId" TEXT NOT NULL,
    "poolId" TEXT,
    "windowStart" TIMESTAMP(3) NOT NULL,
    "windowEnd" TIMESTAMP(3) NOT NULL,
    "seatCount" INTEGER NOT NULL DEFAULT 1,
    "pickupLat" DOUBLE PRECISION NOT NULL,
    "pickupLng" DOUBLE PRECISION NOT NULL,
    "pickupLabel" TEXT NOT NULL,
    "dropoffLat" DOUBLE PRECISION NOT NULL,
    "dropoffLng" DOUBLE PRECISION NOT NULL,
    "dropoffLabel" TEXT NOT NULL,
    "status" "SeatRequestStatus" NOT NULL DEFAULT 'PENDING',
    "bookingId" TEXT,
    "raiseResponse" "RaiseResponse",
    "raiseRespondedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SeatRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Pool" (
    "id" TEXT NOT NULL,
    "corridorId" TEXT NOT NULL,
    "windowStart" TIMESTAMP(3) NOT NULL,
    "windowEnd" TIMESTAMP(3) NOT NULL,
    "totalSeats" INTEGER NOT NULL DEFAULT 0,
    "pricePerSeat" INTEGER NOT NULL,
    "status" "PoolStatus" NOT NULL DEFAULT 'FORMING',
    "claimedByDriverId" TEXT,
    "claimedAt" TIMESTAMP(3),
    "tripId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Pool_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PoolRaise" (
    "id" TEXT NOT NULL,
    "poolId" TEXT NOT NULL,
    "proposedByDriverId" TEXT NOT NULL,
    "oldPricePerSeat" INTEGER NOT NULL,
    "newPricePerSeat" INTEGER NOT NULL,
    "respondBy" TIMESTAMP(3) NOT NULL,
    "resolvedAt" TIMESTAMP(3),
    "outcome" "PoolRaiseOutcome",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PoolRaise_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SeatRequest_riderId_status_createdAt_idx" ON "SeatRequest"("riderId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "SeatRequest_poolId_status_idx" ON "SeatRequest"("poolId", "status");

-- CreateIndex
CREATE INDEX "Pool_corridorId_status_windowStart_idx" ON "Pool"("corridorId", "status", "windowStart");

-- CreateIndex
CREATE INDEX "Pool_status_windowEnd_idx" ON "Pool"("status", "windowEnd");

-- CreateIndex
CREATE UNIQUE INDEX "PoolRaise_poolId_key" ON "PoolRaise"("poolId");

-- CreateIndex
CREATE INDEX "PoolRaise_resolvedAt_respondBy_idx" ON "PoolRaise"("resolvedAt", "respondBy");

-- AddForeignKey
ALTER TABLE "SeatRequest" ADD CONSTRAINT "SeatRequest_corridorId_fkey" FOREIGN KEY ("corridorId") REFERENCES "Corridor"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SeatRequest" ADD CONSTRAINT "SeatRequest_poolId_fkey" FOREIGN KEY ("poolId") REFERENCES "Pool"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Pool" ADD CONSTRAINT "Pool_corridorId_fkey" FOREIGN KEY ("corridorId") REFERENCES "Corridor"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PoolRaise" ADD CONSTRAINT "PoolRaise_poolId_fkey" FOREIGN KEY ("poolId") REFERENCES "Pool"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
