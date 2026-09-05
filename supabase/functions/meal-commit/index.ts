import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { currentUserId, userClient } from "../_shared/db.ts";
import { handleMealWrite } from "../_shared/meal-operation.ts";

Deno.serve((req) =>
  handleMealWrite(req, "create", {
    authenticate: currentUserId,
    budget: (request) =>
      enforceRequestBudget(userClient(request), "meal-commit"),
    existingMeal: async (request, operationId) => {
      const { data, error } = await userClient(request).from("meals").select(
        "id",
      )
        .eq("client_op_id", operationId).maybeSingle();
      if (error) throw new Error("Legacy operation lookup failed");
      return data?.id ?? null;
    },
    canonicalMeal: async (request, operationId) => {
      const { data, error } = await userClient(request).from("meals")
        .select("id,user_day,slot,text_input,kcal,protein_g,carb_g,fat_g,confidence,model_version,deleted_at")
        .eq("client_op_id", operationId).maybeSingle();
      if (error) throw new Error("Canonical meal lookup failed");
      if (!data) return null;
      const { text_input, ...fields } = data;
      return { ...fields, name: text_input };
    },
    apply: async (request, args) =>
      await userClient(request).rpc("apply_meal_operation", args),
  })
);
