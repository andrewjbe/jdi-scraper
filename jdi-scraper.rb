require 'selenium-webdriver'
require 'fileutils'
require 'date'
require 'dotenv/load'
require 'zip'
require 'pathname'

class JdiScraper
  BASE_URL = "https://jaildatainitiative.org/roster"
  OUTPUT_DIR = Pathname.new(__dir__).join("data").expand_path

  def initialize(counties, start_date, end_date)
    @counties = counties
    @start_date = Date.parse(start_date)
    @end_date = Date.parse(end_date)
    setup_browser
  end

  def setup_browser
    OUTPUT_DIR.mkpath
    @options = Selenium::WebDriver::Chrome::Options.new
    @options.add_argument('--window-position=0,0') # this is just for andrew's dev convenience
    @options.add_argument('--window-size=1280,1024')
    @driver = Selenium::WebDriver.for :chrome, options: @options
    @wait = Selenium::WebDriver::Wait.new(timeout: 15)
  end

  def login
    puts "Navigating to home page..."
    @driver.navigate.to "https://jaildatainitiative.org/"

    puts "Clicking landing page Login button..."
    begin
      login_trigger = @wait.until do
        @driver.find_element(:xpath, "//button[contains(., 'LOG IN')]")
      end
      login_trigger.click
    rescue => e
      puts "Could not find initial Login button!"
      exit
    end

    puts "Entering credentials on OAuth page..."
    @wait.until { @driver.find_element(:xpath, '//*[@id="email"]') }.send_keys(ENV['JDI_EMAIL'])
    @driver.find_element(:xpath, '//*[@id="password"]').send_keys(ENV['JDI_PASSWORD'])

    submit_button = @driver.find_element(:css, 'button[type="submit"]')
    submit_button.click

    @wait.until { @driver.current_url.include?("jaildatainitiative.org") }
    puts "Login successful!\n------------------------------------------------------"
  rescue => e
    puts "Login failed: #{e.message}"
    @driver.quit; exit
  end

  def run
    puts "======================================================\nBeginning new scrape\n======================================================"
    start_time = Time.now

    login
    sleep 3

    @counties.each do |display_name, url_slug|
      (@start_date..@end_date).each do |current_date|
        date_str = current_date.strftime("%Y-%m-%d")

        current_download_dir = OUTPUT_DIR.join(display_name.downcase, date_str)

        # skip if we already have the CSVs
        if Dir.glob(current_download_dir.join("*.csv")).any?
          puts " --- Skipping #{date_str}: Files already exist."
          next
        end

        current_download_dir.mkpath

        # set chrome download location
        @driver.execute_cdp("Browser.setDownloadBehavior",
                            behavior: "allow",
                            downloadPath: current_download_dir.to_s,
                            eventsEnabled: true
        )

        target_url = "#{BASE_URL}?state=OK&jail=#{display_name}&date=#{date_str}"
        puts "\nChecking roster for county: #{display_name} and date: #{date_str}..."
        @driver.navigate.to target_url

        begin
          download_btn = @wait.until do
            element = @driver.find_element(:xpath, "//button[contains(., 'Original CSV')]")
            element if element.displayed? && element.enabled?
          end

          # click the button regardless of if the loading UI is in the way
          @driver.execute_script("arguments[0].click();", download_btn)

          handle_download(display_name, date_str, current_download_dir)

        rescue Selenium::WebDriver::Error::TimeoutError
          puts "Error: No data found (Timeout looking for button)."
        rescue => e
          puts "Error: #{e.message}"
        end
      end
    end

    stop_time = Time.now
    scrape_time = stop_time - start_time
    pretty_time = Time.at(scrape_time).utc.strftime("%H hours, %M minutes, %S seconds")
    puts "======================================================\nScrape Completed! Total time: #{pretty_time}\n======================================================"

  end

  private

  def handle_download(county, date, target_dir)
    # make sure the download is finished
    @wait.until do
      Dir.glob(target_dir.join("*.zip")).any? &&
        Dir.glob(target_dir.join("*.crdownload")).empty?
    end

    zip_path = Pathname.glob(target_dir.join("*.zip")).first
    return puts "Zip not found!!" unless zip_path
    puts "Extracting contents from #{zip_path.basename}"

    Zip::File.open(zip_path) do |zip|
      zip.select { |e| e.file? && e.name.downcase.end_with?('.csv') }.each do |entry|

        original_base = File.basename(entry.name, ".*").downcase
        new_filename = "#{original_base}-#{county.downcase}-#{date}.csv"
        dest_path = target_dir.join(new_filename)

        puts "Extracting to: #{dest_path}"

        File.open(dest_path, "wb") do |f|
          f.write(entry.get_input_stream.read)
        end

        # This wasn't working for some reason:
        # entry.extract(dest_path) { true }

      end
    end
  end
end

COUNTIES = {
  "Atoka" => "atoka",
  "Blaine" => "blaine",
  "Caddo" => "caddo",
  "Canadian" => "canadian",
  "Carter" => "carter",
  "Cimarron" => "cimarron",
  "Cleveland" => "cleveland",
  "Comanche" => "comanche",
  "Craig" => "craig",
  "Creek" => "creek",
  "Custer" => "custer",
  "Delaware" => "delaware",
  "Garfield" => "garfield",
  "Garvin" => "garvin",
  "Grady" => "grady",
  "Latimer" => "latimer",
  "Lincoln" => "lincoln",
  "Logan" => "logan",
  "Love" => "love",
  "Major" => "major",
  "Mayes" => "mayes",
  "McClain" => "mcclain",
  "Oklahoma" => "oklahoma",
  "Okmulgee" => "okmulgee",
  "Osage" => "osage",
  "Ottawa" => "ottawa",
  "Pawnee" => "pawnee",
  "Payne" => "payne",
  "Pottawatomie" => "pottawatomie",
  "Rogers" => "rogers",
  "Seminole" => "seminole",
  "Sequoyah" => "sequoyah",
  "Tulsa" => "tulsa",
  "Wagoner" => "wagoner",
  "Washington" => "washington"
}
scraper = JdiScraper.new(COUNTIES, "2025-12-01", Date.today.strftime("%Y-%m-%d"))
scraper.run