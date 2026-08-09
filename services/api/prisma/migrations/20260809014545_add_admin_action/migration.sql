-- CreateEnum
CREATE TYPE "AdminActionType" AS ENUM ('BOOKING_CANCELLED', 'TRIP_CANCELLED', 'DRIVER_SUSPENDED', 'DRIVER_UNSUSPENDED', 'NO_SHOW_VOIDED', 'NO_SHOW_BLOCK_LIFTED');

-- CreateTable
CREATE TABLE "AdminAction" (
    "id" TEXT NOT NULL,
    "adminId" TEXT NOT NULL,
    "adminUsername" TEXT NOT NULL,
    "type" "AdminActionType" NOT NULL,
    "entityType" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminAction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AdminAction_adminId_createdAt_idx" ON "AdminAction"("adminId", "createdAt");

-- CreateIndex
CREATE INDEX "AdminAction_entityType_entityId_createdAt_idx" ON "AdminAction"("entityType", "entityId", "createdAt");
