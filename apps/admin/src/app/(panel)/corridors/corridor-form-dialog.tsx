"use client";

import { useEffect, useState } from "react";
import { useForm, type Control } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormMessage,
} from "@/components/ui/form";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { IRAQI_CITIES } from "@/lib/cities";
import type { Corridor } from "@/lib/types";
import {
  corridorFormSchema,
  type CorridorFormValues,
} from "./corridor-form-schema";
import { createCorridorAction, updateCorridorAction } from "./actions";

interface CorridorFormDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Present → edit mode; absent → create mode. */
  corridor?: Corridor;
}

export function CorridorFormDialog({
  open,
  onOpenChange,
  corridor,
}: CorridorFormDialogProps) {
  const isEdit = Boolean(corridor);
  const [active, setActive] = useState(corridor?.active ?? true);
  const [formError, setFormError] = useState<string | null>(null);

  const form = useForm<CorridorFormValues>({
    resolver: zodResolver(corridorFormSchema),
    defaultValues: defaultsFor(corridor),
  });

  // Reset the form whenever the dialog is (re-)opened for a (possibly
  // different) corridor, so stale values from a previous edit don't linger.
  useEffect(() => {
    if (open) {
      form.reset(defaultsFor(corridor));
      setActive(corridor?.active ?? true);
      setFormError(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, corridor]);

  const originCity = form.watch("originCity");
  const destCity = form.watch("destCity");

  async function onSubmit(values: CorridorFormValues) {
    setFormError(null);
    const result = isEdit
      ? await updateCorridorAction(corridor!.id, { ...values, active })
      : await createCorridorAction(values);

    if (!result.ok) {
      setFormError(result.message);
      toast.error(result.message);
      return;
    }

    toast.success(isEdit ? "تم حفظ التغييرات" : "تم إنشاء الممر");
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? "تعديل الممر" : "أنشئ ممراً جديداً"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "عدّل الأسعار أو المسار، أو بدّل حالة التفعيل."
              : "اختر مدينتي الانطلاق والوصول، ثم حدّد السعر المقترح وحدّي السماح."}
          </DialogDescription>
        </DialogHeader>

        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="grid gap-4">
            <FormField
              control={form.control}
              name="originCity"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>من</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="اختر مدينة الانطلاق" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {IRAQI_CITIES.filter((c) => c.key !== destCity).map((c) => (
                        <SelectItem key={c.key} value={c.key}>
                          {c.ar}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <FormField
              control={form.control}
              name="destCity"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>إلى</FormLabel>
                  <Select value={field.value} onValueChange={field.onChange}>
                    <FormControl>
                      <SelectTrigger>
                        <SelectValue placeholder="اختر مدينة الوصول" />
                      </SelectTrigger>
                    </FormControl>
                    <SelectContent>
                      {IRAQI_CITIES.filter((c) => c.key !== originCity).map((c) => (
                        <SelectItem key={c.key} value={c.key}>
                          {c.ar}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <FormMessage />
                </FormItem>
              )}
            />

            <fieldset className="grid gap-4 rounded-md border border-border p-3">
              <legend className="px-1 text-sm font-medium text-muted-foreground">
                التسعير (IQD)
              </legend>
              <p className="text-xs text-muted-foreground">
                السائق يحدد سعر المقعد عند نشر الرحلة. المقترح هو ما يُملأ له
                مسبقاً، والحدّان هما ما لا يستطيع تجاوزه.
              </p>

              <PriceField
                control={form.control}
                name="minPricePerSeat"
                label="أدنى سعر"
              />
              <PriceField
                control={form.control}
                name="suggestedPricePerSeat"
                label="السعر المقترح"
              />
              <PriceField
                control={form.control}
                name="maxPricePerSeat"
                label="أعلى سعر"
              />
            </fieldset>

            {isEdit && (
              <div className="flex items-center justify-between rounded-md border border-border px-3 py-3">
                <Label htmlFor="active-toggle" className="cursor-pointer">
                  الممر نشط (قابل للحجز والنشر)
                </Label>
                <Switch id="active-toggle" checked={active} onCheckedChange={setActive} />
              </div>
            )}

            {formError && (
              <p role="alert" className="text-sm font-medium text-destructive">
                {formError}
              </p>
            )}

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => onOpenChange(false)}
                disabled={form.formState.isSubmitting}
              >
                إلغاء
              </Button>
              <Button type="submit" disabled={form.formState.isSubmitting}>
                {form.formState.isSubmitting && (
                  <Loader2 className="size-4 animate-spin" />
                )}
                {isEdit ? "حفظ" : "إنشاء"}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}

/** The form's shape for a corridor, or blank fields for a new one. */
function defaultsFor(corridor?: Corridor): CorridorFormValues {
  const blank = "" as unknown as number;
  return {
    originCity: (corridor?.originCity ?? "") as CorridorFormValues["originCity"],
    destCity: (corridor?.destCity ?? "") as CorridorFormValues["destCity"],
    minPricePerSeat: corridor?.minPricePerSeat ?? blank,
    suggestedPricePerSeat: corridor?.suggestedPricePerSeat ?? blank,
    maxPricePerSeat: corridor?.maxPricePerSeat ?? blank,
  };
}

/**
 * One of the three price inputs. `dir="ltr"` keeps digits running the way a
 * numeric keyboard produces them inside the RTL form — the same Western-input
 * rule the phone and OTP fields follow in the apps.
 */
function PriceField({
  control,
  name,
  label,
}: {
  control: Control<CorridorFormValues>;
  name: "minPricePerSeat" | "suggestedPricePerSeat" | "maxPricePerSeat";
  label: string;
}) {
  return (
    <FormField
      control={control}
      name={name}
      render={({ field }) => (
        <FormItem>
          <FormLabel>{label}</FormLabel>
          <FormControl>
            <Input
              type="number"
              inputMode="numeric"
              min={1}
              step={1}
              dir="ltr"
              className="text-start"
              {...field}
            />
          </FormControl>
          <FormMessage />
        </FormItem>
      )}
    />
  );
}
