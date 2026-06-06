import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const NAV_ITEMS = [
    {
        id: 'checking',
        label: 'Checking',
        icon: 'utility:money',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'savings',
        label: 'Savings',
        icon: 'utility:piggybank',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'creditCard',
        label: 'Credit Card',
        icon: 'utility:credit_card',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'smallBusiness',
        label: 'Small Business',
        icon: 'utility:store',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'loans',
        label: 'Loans',
        icon: 'utility:currency',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'mortgage',
        label: 'Mortgage',
        icon: 'utility:home',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'premierBanking',
        label: 'Premier Banking',
        icon: 'utility:people',
        knowledgeArticleUrl: null,
        isActive: false
    },
    {
        id: 'creditScore',
        label: 'Help with Credit Score',
        icon: 'utility:chart',
        knowledgeArticleUrl: '/s/article/understanding-your-credit-score',
        isActive: false
    }
];

export default class FinancialServicesHub extends NavigationMixin(LightningElement) {
    @api hubTitle = 'What can we help you with?';
    @track navItems = NAV_ITEMS.map(item => ({
        ...item,
        cssClass: 'hub-nav-item'
    }));

    @track activeId = null;
    @track isAtStart = true;
    @track isAtEnd = false;

    get showCreditCard() {
        return this.activeId === 'creditCard';
    }

    get showDefault() {
        return !this.activeId;
    }

    handleNavClick(event) {
        const clickedId = event.currentTarget.dataset.id;

        this.navItems = this.navItems.map(item => ({
            ...item,
            isActive: item.id === clickedId,
            cssClass: item.id === clickedId ? 'hub-nav-item hub-nav-item--active' : 'hub-nav-item'
        }));

        const item = NAV_ITEMS.find(i => i.id === clickedId);

        if (item && item.knowledgeArticleUrl) {
            // Navigate to the Knowledge Article in Experience Cloud
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: item.knowledgeArticleUrl
                }
            });
        } else {
            this.activeId = clickedId;
        }
    }

    scrollLeft() {
        const track = this.template.querySelector('[data-id="track"]');
        if (track) {
            track.scrollBy({ left: -220, behavior: 'smooth' });
        }
    }

    scrollRight() {
        const track = this.template.querySelector('[data-id="track"]');
        if (track) {
            track.scrollBy({ left: 220, behavior: 'smooth' });
        }
    }

    handleScroll(event) {
        const track = event.target;
        this.isAtStart = track.scrollLeft === 0;
        this.isAtEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 4;
    }
}

