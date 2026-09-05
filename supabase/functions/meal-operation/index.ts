import { enforceRequestBudget } from "../_shared/rate-limit.ts";
import { currentUserId, userClient } from "../_shared/db.ts";
import { handleMealWrite } from "../_shared/meal-operation.ts";

Deno.serve((req) =>
  handleMealWrite(req, "operation", {
    authenticate: currentUserId,
    budget: (request) =>
      enforceRequestBudget(userClient(request), "meal-operation"),
    existingMeal: () => Promise.resolve(null),
    apply: async (request, args) =>
      await userClient(request).rpc("apply_meal_operation", args),
  })
);
