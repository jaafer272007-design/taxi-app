import { z } from "zod";

import { CITY_KEY_TUPLE } from "@/lib/cities";

const priceField = (label: string) =>
  z.coerce
    .number({ invalid_type_error: `أدخل ${label} كرقم صحيح.` })
    .int({ message: `${label} يجب أن يكون رقماً صحيحاً.` })
    .min(1, { message: `${label} يجب أن يكون أكبر من صفر.` });

/**
 * The corridor no longer carries THE price — the driver sets that when posting.
 * What the admin manages here is the suggestion drivers see prefilled, and the
 * band their price has to land inside.
 *
 * The ordering rule (min <= suggested <= max) is checked with `superRefine` so
 * each violation attaches to the FIELD that is wrong. A form-level banner would
 * leave the admin to work out which of three numbers to change.
 */
export const corridorFormSchema = z
  .object({
    originCity: z.enum(CITY_KEY_TUPLE, {
      errorMap: () => ({ message: "اختر مدينة الانطلاق." }),
    }),
    destCity: z.enum(CITY_KEY_TUPLE, {
      errorMap: () => ({ message: "اختر مدينة الوصول." }),
    }),
    // Ordered the way the constraint reads: min <= suggested <= max.
    minPricePerSeat: priceField("أدنى سعر"),
    suggestedPricePerSeat: priceField("السعر المقترح"),
    maxPricePerSeat: priceField("أعلى سعر"),
  })
  .refine((v) => v.originCity !== v.destCity, {
    message: "لا يمكن أن تكون مدينة الانطلاق والوصول متطابقتين.",
    path: ["destCity"],
  })
  .superRefine((v, ctx) => {
    const min = v.minPricePerSeat;
    const suggested = v.suggestedPricePerSeat;
    const max = v.maxPricePerSeat;

    // An empty field coerces to NaN and already has its own "required" error;
    // piling a range error on top of it is noise, not help.
    if (![min, suggested, max].every(Number.isFinite)) return;

    if (min > max) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["maxPricePerSeat"],
        message: "أعلى سعر يجب ألّا يقل عن أدنى سعر.",
      });
      // The band itself is inverted — suggestion errors on top would just be
      // consequences of the same mistake.
      return;
    }
    if (suggested < min) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["suggestedPricePerSeat"],
        message: "السعر المقترح يجب ألّا يقل عن أدنى سعر.",
      });
    }
    if (suggested > max) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["suggestedPricePerSeat"],
        message: "السعر المقترح يجب ألّا يزيد على أعلى سعر.",
      });
    }
  });

export type CorridorFormValues = z.infer<typeof corridorFormSchema>;
