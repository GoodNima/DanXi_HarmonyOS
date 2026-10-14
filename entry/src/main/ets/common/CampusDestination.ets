/** Keep old card links valid while each new service has its own detail flow. */
export class CampusDestination {
  static page(feature: string): string {
    if (feature === 'empty_classroom') return 'pages/ClassroomSchedulePage'
    if (feature === 'library_books') return 'pages/LibraryBooksPage'
    if (feature === 'sports') return 'pages/SportsBookingPage'
    if (['evaluation', 'campus_access', 'life_code'].includes(feature)) return 'pages/CampusUtilityPage'
    if (['developer_notice', 'dining', 'library', 'electricity'].includes(feature)) return 'pages/CampusLiveServicesPage'
    return 'pages/CampusDetailPage'
  }
}
