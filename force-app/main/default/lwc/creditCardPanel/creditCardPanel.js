import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

// Update these URLs to match your Experience Cloud site slug and article URL names
const ARTICLE_ENJOY_BEYOND   = '/s/article/truist-enjoy-beyond-credit-card';
const APPLY_URL              = 'https://www.truist.com/credit-cards/enjoy-beyond/apply';
const RATES_URL              = 'https://www.truist.com/credit-cards/enjoy-beyond#disc1';

export default class CreditCardPanel extends NavigationMixin(LightningElement) {

    navigateToLearnMore() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: ARTICLE_ENJOY_BEYOND
            }
        });
    }

    navigateToApply() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: APPLY_URL
            }
        });
    }

    navigateToRates() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: RATES_URL
            }
        });
    }
}
