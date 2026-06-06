# Agentforce Topic: Credit Card Advisor
# Configure this topic in Setup → Agentforce → Agents → [Your Agent] → Topics → New

## Topic Details
- **Topic Label:** Credit Card Advisor
- **Developer Name:** Credit_Card_Advisor
- **Description (shown to planner — be precise):**
  Handle all customer inquiries about Truist credit card products including rewards structures,
  fees, APR, travel benefits, welcome bonuses, Loyalty Cash Bonus, and card comparisons.
  Applicable cards include: Enjoy Beyond, Enjoy Cash (3-2-1 and 1.5%), Enjoy Travel, and Future.
  Use when the customer asks "what card should I get", "tell me about the Enjoy Beyond",
  "how do points work", "what is the annual fee", or any question about credit card features.
  Do NOT use for billing disputes, payment processing, or account-specific inquiries.

## Scope
- Questions about Truist credit card features, rewards, fees, APR, and eligibility criteria
- Card comparisons and recommendations
- Travel credits, TSA PreCheck/Global Entry credit details
- Loyalty Cash Bonus explanation
- Welcome bonus/sign-up offer clarification

## Instructions for the Agent
1. Identify which card(s) the customer is asking about (or all cards for comparison requests).
2. Search Knowledge for the relevant Knowledge Article(s).
3. If a Knowledge Article is found:
   a. Optionally call **Summarize Knowledge Article** to generate a conversational summary.
   b. Pass the article body to **Answer Credit Card Questions** with the customer's question.
   c. Return the generated response to the customer.
4. If no Knowledge Article is found, escalate to a human agent or provide the Truist contact number: 844-4TRUIST (844-487-8478).
5. Never fabricate rates, fees, or benefit details.

## Actions to Configure
| Order | Action | Type | Notes |
|-------|--------|------|-------|
| 1 | Search Knowledge | Platform (built-in) | Search query = customer's question; return top 3 articles |
| 2 | Summarize Knowledge Article | Prompt Template (GenAiFunction) | Optional; use for longer articles |
| 3 | Answer Credit Card Questions | Prompt Template (GenAiFunction) | Pass KnowledgeContext + CustomerQuestion |

## Recommended Knowledge Articles to Publish
- truist-enjoy-beyond-credit-card (article created in this package)
- truist-enjoy-cash-credit-card
- truist-enjoy-travel-credit-card
- truist-future-credit-card
- understanding-your-credit-score (article created in this package)
